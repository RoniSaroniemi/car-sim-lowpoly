"""Pure-Python cabin envelope checks, independent of Blender and a vehicle mesh."""
import math

def validate_config(config):
    if config.get('schema_version')!=1: raise ValueError('Unsupported interior schema version')
    env=config['envelope']; stations=env['stations']
    if len(stations)<2 or any(a['x']>=b['x'] for a,b in zip(stations,stations[1:])):
        raise ValueError('Envelope stations must have strictly increasing X positions')
    for st in stations:
        if any(not math.isfinite(st[k]) for k in ['x','roof_z','half_width_floor','half_width_roof']):
            raise ValueError('Envelope values must be finite')
        if st['roof_z']<=env['floor_z'] or min(st['half_width_floor'],st['half_width_roof'])<=0:
            raise ValueError('Envelope needs positive cabin height and widths')
    if not 0<config['glass']['alpha']<1: raise ValueError('Glass alpha must be between zero and one')
    for key in ['front_seats','rear_bench']:
        for field in ['width','depth','cushion_thickness','back_height','back_thickness']:
            if not math.isfinite(config[key][field]) or config[key][field]<=0:
                raise ValueError(f'{key}.{field} must be a positive finite dimension')
    policy=config['fit']
    if not 0<policy['minimum_scale']<=1 or not 0<policy['scale_step']<1:
        raise ValueError('Invalid fit policy')
    for name,values in [('dashboard.center',config['dashboard']['center']),('steering.center',config['steering']['center']),('steering.axis',config['steering']['axis'])]:
        if len(values)!=3 or any(not math.isfinite(x) for x in values):raise ValueError(name+' must contain three finite numbers')
    for name,values in [('dashboard.size',config['dashboard']['size'])]+[(p['name']+'.size',p['size']) for p in config.get('boundary_panels',[])]:
        if len(values)!=3 or min(values)<=0 or any(not math.isfinite(x) for x in values):raise ValueError(name+' needs three positive finite dimensions')
    if sum(x*x for x in config['steering']['axis'])<1e-8 or config['steering']['radius']<=config['steering']['tube_radius']:
        raise ValueError('Invalid steering axis or rim dimensions')

def station_at(env,x):
    stations=env['stations']
    if x<=stations[0]['x']: return stations[0]
    if x>=stations[-1]['x']: return stations[-1]
    for a,b in zip(stations,stations[1:]):
        if x<=b['x']:
            t=(x-a['x'])/(b['x']-a['x'])
            return {k:a[k]+(b[k]-a[k])*t for k in a}

def clearance_at(env,p):
    x,y,z=p; st=station_at(env,x)
    t=max(0,min(1,(z-env['floor_z'])/(st['roof_z']-env['floor_z'])))
    half=st['half_width_floor']+(st['half_width_roof']-st['half_width_floor'])*t
    return min(x-env['stations'][0]['x'],env['stations'][-1]['x']-x,
               z-env['floor_z'],st['roof_z']-z,half-abs(y))

def fit_points(points,env,anchor,policy):
    """Conservatively shrink around a component anchor; never expand it.

    Returns a scale and clearance. Raises rather than silently exporting a part
    that cannot fit. Contact trim/lining is handled separately by the modeler.
    """
    required=env['clearance']; scale=1.0
    while scale>=policy['minimum_scale']-1e-8:
        fitted=[tuple(a+(v-a)*scale for v,a in zip(p,anchor)) for p in points]
        gap=min(clearance_at(env,p) for p in fitted)
        if gap>=required-1e-8: return scale,gap
        if not policy['auto_fit']: break
        scale=round(scale-policy['scale_step'],8)
    raise ValueError(f'Component cannot fit: minimum allowed scale {policy["minimum_scale"]}, clearance {required} m. Adjust placement or the envelope.')

def boundary_clearance_at(env,p,allowance):
    """Looser documented limits for intentional lining-adjacent trim surfaces."""
    x,y,z=p;st=station_at(env,x)
    t=max(0,min(1,(z-env['floor_z'])/(st['roof_z']-env['floor_z'])))
    half=st['half_width_floor']+(st['half_width_roof']-st['half_width_floor'])*t
    return min(x-env['stations'][0]['x']+allowance['x'],env['stations'][-1]['x']+allowance['x']-x,
               z-env['floor_z']+allowance['floor'],st['roof_z']+allowance['roof']-z,half+allowance['y']-abs(y))
