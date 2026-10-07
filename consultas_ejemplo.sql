-- Ejecuta una consulta a la vez en pgAdmin Query Tool.

-- Ver las 27 tablas del modelo.
select table_name
from information_schema.tables
where table_schema = 'public' and table_type = 'BASE TABLE'
order by table_name;

-- Datos iniciales que sí incluye la migración.
select id_combustible, nombre, estado
from public.combustible
order by id_combustible;

select codigo, valor, descripcion
from public.parametro_sistema
order by codigo;

-- Estas tablas estarán vacías hasta registrar datos de ejemplo.
select id_persona, ci, nombres, apellidos, estado
from public.persona
order by id_persona;

select c.id_carga, c.fecha_hora_inicio, p.nombres, p.apellidos,
       v.placa, e.nombre as estacion, c.litros_despachados, c.estado
from public.carga as c
join public.persona as p on p.id_persona = c.id_persona
join public.vehiculo as v on v.id_vehiculo = c.id_vehiculo
join public.estacion as e on e.id_estacion = c.id_estacion
order by c.fecha_hora_inicio desc;

