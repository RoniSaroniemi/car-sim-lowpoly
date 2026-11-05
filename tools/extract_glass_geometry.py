#!/usr/bin/env python3
"""Extract actual GLB glazing into the car-effects profile (standard library only)."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2),
              5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def add(a, b):
    return [x + y for x, y in zip(a, b)]


def subtract(a, b):
    return [x - y for x, y in zip(a, b)]


def multiply(a, scalar):
    return [x * scalar for x in a]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0]]


def normalized(a):
    length = math.sqrt(dot(a, a))
    if length < 1e-12:
        raise ValueError('Cannot normalize a degenerate geometry axis')
    return multiply(a, 1.0 / length)


def load_glb(path):
    data = path.read_bytes()
    magic, version, total_length = struct.unpack_from('<III', data)
    if magic != 0x46546C67 or version != 2 or total_length != len(data):
        raise ValueError(f'Expected a valid glTF 2 GLB: {path}')
    chunks = {}
    offset = 12
    while offset < len(data):
        size, kind = struct.unpack_from('<II', data, offset)
        offset += 8
        chunks[kind] = data[offset:offset + size]
        offset += size
    document = json.loads(chunks[0x4E4F534A])
    return document, chunks[0x004E4942], data


def accessor(document, binary, index):
    item = document['accessors'][index]
    if 'sparse' in item:
        raise ValueError('Sparse geometry accessors are not supported')
    view = document['bufferViews'][item['bufferView']]
    if view.get('buffer', 0) != 0:
        raise ValueError('Only the embedded GLB buffer is supported')
    character, size = COMPONENTS[item['componentType']]
    width = WIDTHS[item['type']]
    count = item['count']
    byte_offset = view.get('byteOffset', 0) + item.get('byteOffset', 0)
    stride = view.get('byteStride', size * width)
    if stride < size * width:
        raise ValueError('Accessor stride is smaller than the element size')
    return [list(struct.unpack_from('<' + character * width, binary,
                                    byte_offset + i * stride))
            for i in range(count)]


def apply_node(point, node):
    if 'matrix' in node:
        if any(key in node for key in ('translation', 'rotation', 'scale')):
            raise ValueError('A glTF node cannot combine matrix and TRS')
        m = node['matrix']
        if len(m) != 16 or any(abs(m[i]) > 1e-8 for i in (3, 7, 11)) or abs(m[15] - 1) > 1e-8:
            raise ValueError('Expected an affine column-major glTF matrix')
        x, y, z = point
        return [m[0] * x + m[4] * y + m[8] * z + m[12],
                m[1] * x + m[5] * y + m[9] * z + m[13],
                m[2] * x + m[6] * y + m[10] * z + m[14]]
    result = [x * s for x, s in zip(point, node.get('scale', [1, 1, 1]))]
    q = node.get('rotation', [0, 0, 0, 1])
    q_length = math.sqrt(sum(x * x for x in q))
    if q_length < 1e-12:
        raise ValueError('Degenerate node quaternion')
    xyz = [q[i] / q_length for i in range(3)]
    w = q[3] / q_length
    turn = multiply(cross(xyz, result), 2)
    result = add(result, add(multiply(turn, w), cross(xyz, turn)))
    return add(result, node.get('translation', [0, 0, 0]))


def convex_hull(points):
    # UVs on a source edge can differ by tiny projection noise. Quantization is
    # limited to the footprint hull; stored vertices and per-vertex UVs stay exact.
    unique = sorted({(round(p[0], 9), round(p[1], 9)) for p in points})

    def turn(a, b, c):
        return ((b[0] - a[0]) * (c[1] - a[1])
                - (b[1] - a[1]) * (c[0] - a[0]))

    lower = []
    for p in unique:
        while len(lower) >= 2 and turn(lower[-2], lower[-1], p) <= 1e-10:
            lower.pop()
        lower.append(p)
    upper = []
    for p in reversed(unique):
        while len(upper) >= 2 and turn(upper[-2], upper[-1], p) <= 1e-10:
            upper.pop()
        upper.append(p)
    hull = lower[:-1] + upper[:-1]
    if len(hull) < 3:
        raise ValueError('Pane has no usable planar footprint')
    return [list(p) for p in hull]


def extract(document, binary):
    parents = {}
    for index, node in enumerate(document['nodes']):
        for child in node.get('children', []):
            if child in parents:
                raise ValueError('A glass hierarchy node has multiple parents')
            parents[child] = index
    panes = []
    for node_index, node in enumerate(document['nodes']):
        name = node.get('name', '')
        if not name.startswith('Glass_'):
            continue
        vertices, indices = [], []
        for primitive in document['meshes'][node['mesh']]['primitives']:
            if primitive.get('mode', 4) != 4:
                raise ValueError(f'{name}: expected triangle primitives')
            if document['accessors'][primitive['attributes']['POSITION']]['componentType'] != 5126:
                raise ValueError(f'{name}: expected float32 vertex positions')
            local_vertices = accessor(document, binary, primitive['attributes']['POSITION'])
            base = len(vertices)
            for point in local_vertices:
                parent = node_index
                visited = set()
                while True:
                    if parent in visited:
                        raise ValueError('Cycle in glTF node hierarchy')
                    visited.add(parent)
                    point = apply_node(point, document['nodes'][parent])
                    if parent not in parents:
                        break
                    parent = parents[parent]
                vertices.append(point)
            if 'indices' in primitive:
                item = document['accessors'][primitive['indices']]
                if item['componentType'] not in (5121, 5123, 5125) or item['type'] != 'SCALAR':
                    raise ValueError(f'{name}: expected unsigned integer indices')
                local_indices = [x[0] for x in accessor(document, binary, primitive['indices'])]
            else:
                local_indices = list(range(len(local_vertices)))
            if len(local_indices) % 3 or any(i < 0 or i >= len(local_vertices) for i in local_indices):
                raise ValueError(f'{name}: invalid triangle indices')
            indices.extend(base + i for i in local_indices)
        origin = [sum(p[axis] for p in vertices) / len(vertices) for axis in range(3)]
        normal = [0.0, 0.0, 0.0]
        for offset in range(0, len(indices), 3):
            a, b, c = [vertices[i] for i in indices[offset:offset + 3]]
            normal = add(normal, cross(subtract(b, a), subtract(c, a)))
        normal = normalized(normal)
        pane_id = name.removeprefix('Glass_').lower()
        if pane_id == 'windscreen':
            expected = [1, 0, 0]
        elif pane_id == 'rear':
            expected = [-1, 0, 0]
        else:
            expected = [0, 0, 1 if origin[2] > 0 else -1]
        if dot(normal, expected) < 0:
            normal = multiply(normal, -1)
        u_axis = normalized(cross([0, 1, 0], normal))
        v_axis = normalized(cross(normal, u_axis))
        projected = [[dot(subtract(p, origin), u_axis),
                      dot(subtract(p, origin), v_axis)] for p in vertices]
        umin, umax = min(p[0] for p in projected), max(p[0] for p in projected)
        vmin, vmax = min(p[1] for p in projected), max(p[1] for p in projected)
        width, height = umax - umin, vmax - vmin
        if min(width, height) <= 1e-6:
            raise ValueError(f'{name}: degenerate pane dimensions')
        uv = [[(p[0] - umin) / width, (p[1] - vmin) / height] for p in projected]
        residual = max(abs(dot(subtract(p, origin), normal)) for p in vertices)
        pane = {
            'id': pane_id,
            'mesh_name': name,
            'material': 'laminated' if pane_id == 'windscreen' else 'tempered',
            'origin': origin,
            'u_axis': u_axis,
            'v_axis': v_axis,
            'normal': normal,
            'width_m': width,
            'height_m': height,
            'uv_bounds': [umin, umax, vmin, vmax],
            'vertices': vertices,
            'indices': indices,
            'uv': uv,
            'outline_uv': convex_hull(uv),
            'maximum_plane_residual_m': residual,
            'source_node_index': node_index,
            'source_mesh_index': node['mesh'],
            'settings': {
                'crack_frame_strain': 0.015,
                'break_frame_strain': 0.04,
                'film_retention': False,
                'grid_x': 12,
                'grid_y': 8,
            },
        }
        panes.append(pane)
    expected_ids = {'windscreen', 'rear', 'door_left', 'door_right', 'quarter_left', 'quarter_right'}
    if {p['id'] for p in panes} != expected_ids or len(panes) != 6:
        raise ValueError('Expected exactly the six Niva glazing panes')
    order = {name: i for i, name in enumerate(('windscreen', 'rear', 'door_left', 'door_right', 'quarter_left', 'quarter_right'))}
    panes.sort(key=lambda pane: order[pane['id']])
    return panes


def build_profile(source):
    document, binary, raw = load_glb(source)
    return {
        'version': 1,
        'id': 'niva_glass_v1',
        'model': 'res://' + source.relative_to(ROOT).as_posix(),
        'model_sha256': hashlib.sha256(raw).hexdigest(),
        'geometry_source': 'Six actual Glass_* GLB meshes, with full ancestor transforms applied.',
        'generator': 'tools/extract_glass_geometry.py',
        'generator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'material_scope': 'Configurable demonstration defaults, not an archival glazing certification.',
        'coordinate_system': 'Car rest space: +X forward, +Y up, +Z asset left.',
        'uv_scope': 'Pane-local planar projection; original rest vertices/triangles preserve non-planar residuals.',
        'panes': extract(document, binary),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / 'assets/Niva_2121_LOD0.glb')
    parser.add_argument('--output', type=Path, default=ROOT / 'vehicles/niva_glass.json')
    args = parser.parse_args()
    source = args.source.resolve()
    profile = build_profile(source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(profile, indent=2, allow_nan=False) + '\n')
    for pane in profile['panes']:
        print(f"{pane['id']}: {len(pane['vertices'])} vertices, {len(pane['indices']) // 3} triangles, "
              f"{pane['width_m']:.4f} x {pane['height_m']:.4f} m, "
              f"plane residual {pane['maximum_plane_residual_m']:.6f} m")
    print('Wrote', args.output)


if __name__ == '__main__':
    main()
