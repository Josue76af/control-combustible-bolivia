-- Sistema académico de control de combustible. Tiempos en timestamptz (UTC en almacenamiento).
-- La semana del cupo se interpreta en America/La_Paz por la aplicación.

create table public.persona (
  id_persona bigint generated always as identity primary key,
  ci text not null unique,
  nombres text not null,
  apellidos text not null,
  telefono text,
  fecha_nacimiento date,
  estado text not null default 'ACTIVA' check (estado in ('ACTIVA', 'INACTIVA')),
  fecha_registro timestamptz not null default now()
);

create table public.combustible (
  id_combustible bigint generated always as identity primary key,
  nombre text not null unique,
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO', 'INACTIVO'))
);

create table public.usuario_sistema (
  id_usuario bigint generated always as identity primary key,
  auth_user_id uuid unique,
  nombres text not null,
  apellidos text not null,
  rol text not null check (rol in ('ADMINISTRADOR', 'SUPERVISOR')),
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO', 'INACTIVO')),
  fecha_registro timestamptz not null default now()
);

create table public.parametro_sistema (
  id_parametro bigint generated always as identity primary key,
  codigo text not null unique,
  valor text not null,
  descripcion text,
  fecha_modificacion timestamptz not null default now()
);

create table public.biometria (
  id_biometria bigint generated always as identity primary key,
  id_persona bigint not null references public.persona(id_persona),
  huella text not null,
  intentos_fallidos integer not null default 0 check (intentos_fallidos >= 0),
  estado text not null default 'ACTIVA' check (estado in ('ACTIVA', 'BLOQUEADA', 'INACTIVA')),
  fecha_registro timestamptz not null default now()
);
comment on column public.biometria.huella is 'Referencia opaca a una plantilla biométrica cifrada en un sistema especializado; nunca imagen ni huella sin cifrar.';
create function public.validar_intentos_huella() returns trigger
language plpgsql set search_path = '' as $$
declare max_intentos integer;
begin
  select valor::integer into max_intentos from public.parametro_sistema
    where codigo = 'MAX_INTENTOS_HUELLA';
  if max_intentos is null or new.intentos_fallidos > max_intentos then
    raise exception 'Se superó el máximo configurado de intentos de huella';
  end if;
  return new;
end;
$$;
create trigger biometria_intentos_trg before insert or update of intentos_fallidos
on public.biometria for each row execute function public.validar_intentos_huella();

create table public.vehiculo (
  id_vehiculo bigint generated always as identity primary key,
  placa text not null unique,
  tipo_vehiculo text not null,
  marca text,
  modelo text,
  anio integer check (anio between 1900 and 2200),
  id_combustible bigint not null references public.combustible(id_combustible),
  capacidad_tanque numeric(10,3) not null check (capacidad_tanque > 0),
  rendimiento_km_l numeric(10,3) check (rendimiento_km_l > 0),
  estado_ruat text not null default 'PENDIENTE' check (estado_ruat in ('PENDIENTE', 'VALIDO', 'OBSERVADO')),
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO', 'INACTIVO')),
  fecha_registro timestamptz not null default now()
);

create table public.persona_vehiculo (
  id_persona_vehiculo bigint generated always as identity primary key,
  id_persona bigint not null references public.persona(id_persona),
  id_vehiculo bigint not null references public.vehiculo(id_vehiculo),
  fecha_inicio timestamptz not null default now(),
  fecha_fin timestamptz,
  motivo_cambio text,
  validado_ruat boolean not null default false,
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO', 'INACTIVO')),
  check (fecha_fin is null or fecha_fin > fecha_inicio),
  check ((estado = 'ACTIVO' and fecha_fin is null) or (estado = 'INACTIVO' and fecha_fin is not null))
);
create unique index persona_vehiculo_vehiculo_activo_uidx
  on public.persona_vehiculo (id_vehiculo) where estado = 'ACTIVO';
create index persona_vehiculo_persona_activo_idx
  on public.persona_vehiculo (id_persona) where estado = 'ACTIVO';

create function public.limitar_vehiculos_activos() returns trigger
language plpgsql set search_path = '' as $$
declare max_vehiculos integer;
begin
  if new.estado = 'ACTIVO' then
    -- Serializa cambios de una misma persona para evitar superar el máximo en concurrencia.
    perform 1 from public.persona where id_persona = new.id_persona for update;
    select valor::integer into max_vehiculos from public.parametro_sistema
      where codigo = 'MAX_VEHICULOS_PERSONA';
    if max_vehiculos is null or max_vehiculos < 1 then
      raise exception 'MAX_VEHICULOS_PERSONA no está configurado correctamente';
    end if;
    if (select count(*) from public.persona_vehiculo
        where id_persona = new.id_persona and estado = 'ACTIVO'
          and id_persona_vehiculo <> coalesce(new.id_persona_vehiculo, -1)) >= max_vehiculos then
      raise exception 'Se superó el máximo configurado de vehículos activos';
    end if;
  end if;
  return new;
end;
$$;
create trigger persona_vehiculo_limite_trg before insert or update of id_persona, estado
on public.persona_vehiculo for each row execute function public.limitar_vehiculos_activos();

create table public.cupo_semanal (
  id_cupo bigint generated always as identity primary key,
  id_persona bigint not null references public.persona(id_persona),
  fecha_inicio date not null,
  fecha_fin date not null,
  litros_asignados numeric(10,3) not null check (litros_asignados > 0),
  litros_consumidos numeric(10,3) not null default 0
    check (litros_consumidos >= 0 and litros_consumidos <= litros_asignados),
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO', 'CERRADO')),
  unique (id_persona, fecha_inicio),
  check (extract(isodow from fecha_inicio) = 1),
  check (fecha_fin = fecha_inicio + 6)
);
comment on table public.cupo_semanal is 'Una fila por persona y semana lunes-domingo de America/La_Paz; no acumulable.';

create table public.precio_combustible (
  id_precio bigint generated always as identity primary key,
  id_combustible bigint not null references public.combustible(id_combustible),
  tipo_precio text not null check (tipo_precio in ('SUBVENCIONADO', 'INTERNACIONAL')),
  precio_litro numeric(12,4) not null check (precio_litro > 0),
  fecha_inicio timestamptz not null,
  fecha_fin timestamptz,
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO', 'INACTIVO')),
  unique (id_combustible, tipo_precio, fecha_inicio),
  check (fecha_fin is null or fecha_fin > fecha_inicio)
);
create unique index precio_combustible_vigente_uidx on public.precio_combustible
  (id_combustible, tipo_precio) where fecha_fin is null and estado = 'ACTIVO';

create table public.estacion (
  id_estacion bigint generated always as identity primary key,
  codigo text not null unique,
  nombre text not null,
  departamento text not null,
  municipio text not null,
  direccion text not null,
  latitud numeric(9,6) check (latitud between -90 and 90),
  longitud numeric(9,6) check (longitud between -180 and 180),
  estado text not null default 'ACTIVA' check (estado in ('ACTIVA', 'INACTIVA')),
  check ((latitud is null) = (longitud is null))
);

create table public.surtidor (
  id_surtidor bigint generated always as identity primary key,
  id_estacion bigint not null references public.estacion(id_estacion),
  numero text not null,
  id_combustible bigint not null references public.combustible(id_combustible),
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO', 'INACTIVO')),
  unique (id_estacion, numero),
  unique (id_surtidor, id_estacion, id_combustible)
);

create table public.tanque_estacion (
  id_tanque bigint generated always as identity primary key,
  id_estacion bigint not null references public.estacion(id_estacion),
  id_combustible bigint not null references public.combustible(id_combustible),
  codigo text not null,
  capacidad_maxima numeric(14,3) not null check (capacidad_maxima > 0),
  cantidad_actual numeric(14,3) not null default 0
    check (cantidad_actual >= 0 and cantidad_actual <= capacidad_maxima),
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO', 'INACTIVO')),
  unique (id_estacion, codigo)
);

create table public.operador (
  id_operador bigint generated always as identity primary key,
  ci text not null unique,
  nombres text not null,
  apellidos text not null,
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO', 'INACTIVO'))
);

create table public.operador_estacion (
  id_operador_estacion bigint generated always as identity primary key,
  id_operador bigint not null references public.operador(id_operador),
  id_estacion bigint not null references public.estacion(id_estacion),
  fecha_inicio timestamptz not null default now(),
  fecha_fin timestamptz,
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO', 'INACTIVO')),
  check (fecha_fin is null or fecha_fin > fecha_inicio),
  check ((estado = 'ACTIVO' and fecha_fin is null) or (estado = 'INACTIVO' and fecha_fin is not null))
);
create unique index operador_estacion_activo_uidx
  on public.operador_estacion (id_operador) where estado = 'ACTIVO';

create table public.carga (
  id_carga bigint generated always as identity primary key,
  id_persona bigint not null references public.persona(id_persona),
  id_vehiculo bigint not null references public.vehiculo(id_vehiculo),
  id_estacion bigint not null references public.estacion(id_estacion),
  id_surtidor bigint not null,
  id_operador bigint not null references public.operador(id_operador),
  id_combustible bigint not null references public.combustible(id_combustible),
  fecha_hora_inicio timestamptz not null default now(),
  fecha_hora_fin timestamptz,
  litros_solicitados numeric(10,3) not null check (litros_solicitados > 0),
  litros_despachados numeric(10,3) not null default 0 check (litros_despachados >= 0),
  modo_offline boolean not null default false,
  estado_sincronizacion text not null default 'SINCRONIZADA'
    check (estado_sincronizacion in ('PENDIENTE', 'SINCRONIZADA', 'ERROR')),
  fecha_sincronizacion timestamptz,
  estado text not null default 'PENDIENTE'
    check (estado in ('PENDIENTE', 'AUTORIZADA', 'EN_PROCESO', 'COMPLETADA', 'RECHAZADA', 'ANULADA')),
  fecha_registro timestamptz not null default now(),
  foreign key (id_surtidor, id_estacion, id_combustible)
    references public.surtidor(id_surtidor, id_estacion, id_combustible),
  check (fecha_hora_fin is null or fecha_hora_fin >= fecha_hora_inicio),
  check (litros_despachados <= litros_solicitados),
  check (modo_offline or estado_sincronizacion = 'SINCRONIZADA')
);
create index carga_vehiculo_fecha_idx on public.carga (id_vehiculo, fecha_hora_inicio desc);
create index carga_persona_fecha_idx on public.carga (id_persona, fecha_hora_inicio desc);
create index carga_estacion_fecha_idx on public.carga (id_estacion, fecha_hora_inicio desc);

create table public.carga_detalle (
  id_detalle bigint generated always as identity primary key,
  id_carga bigint not null references public.carga(id_carga),
  tipo_precio text not null check (tipo_precio in ('SUBVENCIONADO', 'INTERNACIONAL')),
  litros numeric(10,3) not null check (litros > 0),
  precio_unitario numeric(12,4) not null check (precio_unitario > 0),
  subtotal numeric(14,2) generated always as (round(litros * precio_unitario, 2)) stored,
  unique (id_carga, tipo_precio)
);
create function public.validar_detalle_offline() returns trigger
language plpgsql set search_path = '' as $$
declare carga_actual public.carga%rowtype;
        carga_id bigint;
begin
  if tg_op = 'DELETE' then carga_id := old.id_carga;
  else carga_id := new.id_carga; end if;
  select * into carga_actual from public.carga
    where id_carga = carga_id for update;
  if carga_actual.estado = 'COMPLETADA' then
    raise exception 'No se puede cambiar el detalle de una carga completada';
  end if;
  if tg_op <> 'DELETE' and new.tipo_precio = 'SUBVENCIONADO' and carga_actual.modo_offline then
    raise exception 'Una carga offline no puede usar precio subvencionado';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger carga_detalle_offline_trg before insert or update or delete
on public.carga_detalle for each row execute function public.validar_detalle_offline();

create function public.validar_carga() returns trigger
language plpgsql set search_path = '' as $$
declare litros_detalle numeric(10,3);
begin
  if new.modo_offline and exists (
    select 1 from public.carga_detalle
    where id_carga = new.id_carga and tipo_precio = 'SUBVENCIONADO'
  ) then
    raise exception 'Una carga con detalle subvencionado no puede pasar a offline';
  end if;
  if new.estado = 'COMPLETADA' then
    select coalesce(sum(litros), 0) into litros_detalle
      from public.carga_detalle where id_carga = new.id_carga;
    if new.fecha_hora_fin is null or new.litros_despachados <= 0
       or litros_detalle <> new.litros_despachados then
      raise exception 'La carga completada requiere fin y detalle igual a litros despachados';
    end if;
  end if;
  return new;
end;
$$;
create trigger carga_validar_trg before insert or update of estado, modo_offline, litros_despachados
on public.carga for each row execute function public.validar_carga();

create table public.validacion_carga (
  id_validacion bigint generated always as identity primary key,
  id_carga bigint not null references public.carga(id_carga),
  tipo_validacion text not null check (tipo_validacion in
    ('HUELLA', 'PROPIETARIO', 'RUAT', 'CUPO', 'CAPACIDAD_TANQUE', 'FRECUENCIA',
     'DISTANCIA', 'TIEMPO_VIAJE', 'RIESGO', 'BLOQUEO', 'CONEXION')),
  resultado text not null check (resultado in ('APROBADA', 'RECHAZADA', 'OBSERVADA')),
  valor_obtenido text,
  valor_esperado text,
  distancia_km numeric(12,3) check (distancia_km >= 0),
  tiempo_estimado_min numeric(12,2) check (tiempo_estimado_min >= 0),
  tiempo_disponible_min numeric(12,2) check (tiempo_disponible_min >= 0),
  porcentaje_viabilidad numeric(7,2) check (porcentaje_viabilidad >= 0),
  descripcion text,
  fecha_hora timestamptz not null default now()
);
create index validacion_carga_carga_idx on public.validacion_carga(id_carga);

create table public.evidencia_carga (
  id_evidencia bigint generated always as identity primary key,
  id_carga bigint not null references public.carga(id_carga),
  tipo_evidencia text not null,
  ruta_archivo text not null,
  descripcion text,
  fecha_registro timestamptz not null default now()
);

create table public.alerta (
  id_alerta bigint generated always as identity primary key,
  id_persona bigint references public.persona(id_persona),
  id_vehiculo bigint references public.vehiculo(id_vehiculo),
  id_carga bigint references public.carga(id_carga),
  id_estacion bigint references public.estacion(id_estacion),
  tipo_alerta text not null check (tipo_alerta in
    ('CARGA_FRECUENTE', 'VIAJE_IMPOSIBLE', 'POSIBLE_PLACA_CLONADA',
     'EXCESO_CAPACIDAD', 'PATRON_CONSUMO', 'DIFERENCIA_INVENTARIO', 'INTENTO_IRREGULAR')),
  nivel text not null check (nivel in ('BAJA', 'MEDIA', 'ALTA', 'CRITICA')),
  puntaje_riesgo integer check (puntaje_riesgo between 0 and 100),
  descripcion text not null,
  fecha_hora timestamptz not null default now(),
  estado text not null default 'ABIERTA' check (estado in ('ABIERTA', 'EN_REVISION', 'CERRADA'))
);
create index alerta_estado_fecha_idx on public.alerta(estado, fecha_hora desc);

create table public.bloqueo (
  id_bloqueo bigint generated always as identity primary key,
  id_persona bigint references public.persona(id_persona),
  id_vehiculo bigint references public.vehiculo(id_vehiculo),
  id_alerta bigint references public.alerta(id_alerta),
  tipo_bloqueo text not null check (tipo_bloqueo in ('PERSONA', 'VEHICULO')),
  motivo text not null,
  fecha_inicio timestamptz not null default now(),
  fecha_fin timestamptz,
  bloqueo_automatico boolean not null default false,
  id_usuario_desbloqueo bigint references public.usuario_sistema(id_usuario),
  motivo_desbloqueo text,
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO', 'LEVANTADO')),
  check (fecha_fin is null or fecha_fin > fecha_inicio),
  check ((tipo_bloqueo = 'PERSONA' and id_persona is not null and id_vehiculo is null)
      or (tipo_bloqueo = 'VEHICULO' and id_vehiculo is not null and id_persona is null)),
  check ((estado = 'ACTIVO' and fecha_fin is null)
      or (estado = 'LEVANTADO' and fecha_fin is not null and motivo_desbloqueo is not null))
);
create unique index bloqueo_persona_activo_uidx on public.bloqueo(id_persona)
  where estado = 'ACTIVO' and tipo_bloqueo = 'PERSONA';
create unique index bloqueo_vehiculo_activo_uidx on public.bloqueo(id_vehiculo)
  where estado = 'ACTIVO' and tipo_bloqueo = 'VEHICULO';

create table public.reclamo (
  id_reclamo bigint generated always as identity primary key,
  id_persona bigint not null references public.persona(id_persona),
  id_carga bigint not null references public.carga(id_carga),
  motivo text not null,
  descripcion text not null,
  fecha_reclamo timestamptz not null default now(),
  estado text not null default 'PENDIENTE'
    check (estado in ('PENDIENTE', 'EN_REVISION', 'ACEPTADO', 'RECHAZADO')),
  respuesta text,
  fecha_resolucion timestamptz,
  id_usuario_resuelve bigint references public.usuario_sistema(id_usuario),
  check ((estado in ('PENDIENTE', 'EN_REVISION') and fecha_resolucion is null)
      or (estado in ('ACEPTADO', 'RECHAZADO') and fecha_resolucion is not null
          and id_usuario_resuelve is not null))
);
create index reclamo_persona_fecha_idx on public.reclamo(id_persona, fecha_reclamo desc);

create table public.evidencia_reclamo (
  id_evidencia bigint generated always as identity primary key,
  id_reclamo bigint not null references public.reclamo(id_reclamo),
  tipo_evidencia text not null,
  url_archivo text not null,
  descripcion text,
  fecha_registro timestamptz not null default now()
);

create table public.movimiento_cupo (
  id_movimiento_cupo bigint generated always as identity primary key,
  id_cupo bigint not null references public.cupo_semanal(id_cupo),
  id_carga bigint references public.carga(id_carga),
  id_reclamo bigint references public.reclamo(id_reclamo),
  tipo_movimiento text not null check (tipo_movimiento in ('CONSUMO', 'DEVOLUCION', 'AJUSTE')),
  litros numeric(10,3) not null,
  fecha_hora timestamptz not null default now(),
  descripcion text,
  check ((tipo_movimiento in ('CONSUMO', 'DEVOLUCION') and litros > 0)
      or (tipo_movimiento = 'AJUSTE' and litros <> 0)),
  check (tipo_movimiento <> 'CONSUMO' or id_carga is not null),
  check (tipo_movimiento <> 'DEVOLUCION' or (id_carga is not null or id_reclamo is not null))
);
create unique index movimiento_cupo_consumo_carga_uidx on public.movimiento_cupo(id_carga)
  where tipo_movimiento = 'CONSUMO';
create index movimiento_cupo_cupo_fecha_idx on public.movimiento_cupo(id_cupo, fecha_hora);

create function public.aplicar_movimiento_cupo() returns trigger
language plpgsql set search_path = '' as $$
declare
  delta numeric(10,3);
begin
  delta := case new.tipo_movimiento when 'CONSUMO' then new.litros
            when 'DEVOLUCION' then -new.litros else new.litros end;
  update public.cupo_semanal
  set litros_consumidos = litros_consumidos + delta
  where id_cupo = new.id_cupo;
  return new;
end;
$$;
create trigger movimiento_cupo_aplicar_trg after insert on public.movimiento_cupo
for each row execute function public.aplicar_movimiento_cupo();

create table public.recepcion_combustible (
  id_recepcion bigint generated always as identity primary key,
  id_tanque bigint not null references public.tanque_estacion(id_tanque),
  litros_recibidos numeric(14,3) not null check (litros_recibidos > 0),
  fecha_hora timestamptz not null default now(),
  empresa_proveedora text not null,
  placa_cisterna text,
  nombre_conductor text,
  documento_recepcion text,
  id_usuario_registro bigint not null references public.usuario_sistema(id_usuario)
);

create table public.movimiento_inventario (
  id_movimiento bigint generated always as identity primary key,
  id_tanque bigint not null references public.tanque_estacion(id_tanque),
  id_carga bigint references public.carga(id_carga),
  id_recepcion bigint references public.recepcion_combustible(id_recepcion),
  tipo_movimiento text not null check (tipo_movimiento in ('ENTRADA', 'VENTA', 'AJUSTE', 'PERDIDA')),
  cantidad numeric(14,3) not null check (cantidad > 0),
  saldo_anterior numeric(14,3) not null check (saldo_anterior >= 0),
  saldo_nuevo numeric(14,3) not null check (saldo_nuevo >= 0),
  fecha_hora timestamptz not null default now(),
  descripcion text,
  check (tipo_movimiento <> 'ENTRADA' or id_recepcion is not null),
  check (tipo_movimiento <> 'VENTA' or id_carga is not null),
  check ((tipo_movimiento = 'ENTRADA' and saldo_nuevo = saldo_anterior + cantidad)
      or (tipo_movimiento in ('VENTA', 'PERDIDA') and saldo_nuevo = saldo_anterior - cantidad)
      or (tipo_movimiento = 'AJUSTE' and cantidad = abs(saldo_nuevo - saldo_anterior)))
);
create index movimiento_inventario_tanque_fecha_idx
  on public.movimiento_inventario(id_tanque, fecha_hora desc);
create function public.aplicar_movimiento_inventario() returns trigger
language plpgsql set search_path = '' as $$
declare saldo_actual numeric(14,3);
begin
  select cantidad_actual into saldo_actual from public.tanque_estacion
    where id_tanque = new.id_tanque for update;
  if saldo_actual <> new.saldo_anterior then
    raise exception 'El saldo anterior no coincide con el tanque';
  end if;
  update public.tanque_estacion set cantidad_actual = new.saldo_nuevo
    where id_tanque = new.id_tanque;
  return new;
end;
$$;
create trigger movimiento_inventario_aplicar_trg after insert on public.movimiento_inventario
for each row execute function public.aplicar_movimiento_inventario();

create table public.anulacion_carga (
  id_anulacion bigint generated always as identity primary key,
  id_carga bigint not null unique references public.carga(id_carga),
  id_usuario bigint not null references public.usuario_sistema(id_usuario),
  motivo text not null,
  fecha_hora timestamptz not null default now()
);
create function public.aplicar_anulacion_carga() returns trigger
language plpgsql set search_path = '' as $$
begin
  update public.carga set estado = 'ANULADA' where id_carga = new.id_carga;
  return new;
end;
$$;
create trigger anulacion_carga_aplicar_trg after insert on public.anulacion_carga
for each row execute function public.aplicar_anulacion_carga();

create table public.auditoria (
  id_auditoria bigint generated always as identity primary key,
  id_usuario bigint references public.usuario_sistema(id_usuario),
  tabla_afectada text not null,
  id_registro text not null,
  accion text not null check (accion in ('INSERT', 'UPDATE', 'DELETE', 'ANULACION', 'DESBLOQUEO', 'AJUSTE')),
  valores_anteriores jsonb,
  valores_nuevos jsonb,
  fecha_hora timestamptz not null default now(),
  descripcion text
);
create index auditoria_tabla_registro_fecha_idx
  on public.auditoria(tabla_afectada, id_registro, fecha_hora desc);

-- Las tablas contienen identidad, biometría y operaciones. Sin políticas RLS,
-- solo la conexión administrativa puede acceder a ellas.
do $$
declare t text;
begin
  foreach t in array array[
    'persona','combustible','usuario_sistema','parametro_sistema','biometria',
    'vehiculo','persona_vehiculo','cupo_semanal','precio_combustible','estacion',
    'surtidor','tanque_estacion','operador','operador_estacion','carga',
    'carga_detalle','validacion_carga','evidencia_carga','alerta','bloqueo',
    'reclamo','evidencia_reclamo','movimiento_cupo','recepcion_combustible',
    'movimiento_inventario','anulacion_carga','auditoria'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
  end loop;
end $$;

revoke execute on function public.limitar_vehiculos_activos() from public, anon, authenticated;
revoke execute on function public.validar_intentos_huella() from public, anon, authenticated;
revoke execute on function public.validar_detalle_offline() from public, anon, authenticated;
revoke execute on function public.validar_carga() from public, anon, authenticated;
revoke execute on function public.aplicar_movimiento_cupo() from public, anon, authenticated;
revoke execute on function public.aplicar_movimiento_inventario() from public, anon, authenticated;
revoke execute on function public.aplicar_anulacion_carga() from public, anon, authenticated;

insert into public.combustible (nombre) values ('GASOLINA'), ('DIESEL');
insert into public.parametro_sistema (codigo, valor, descripcion) values
  ('CUPO_SEMANAL_LITROS', '30', 'Litros subvencionados por persona y semana'),
  ('MAX_VEHICULOS_PERSONA', '2', 'Máximo de vehículos activos por persona'),
  ('MAX_INTENTOS_HUELLA', '5', 'Máximo de intentos biométricos fallidos'),
  ('RIESGO_BLOQUEO_AUTOMATICO', '85', 'Umbral inicial de bloqueo automático'),
  ('RIESGO_BAJO_DESDE', '30', 'Umbral inicial de riesgo bajo'),
  ('RIESGO_MEDIO_DESDE', '50', 'Umbral inicial de riesgo medio'),
  ('RIESGO_ALTO_DESDE', '70', 'Umbral inicial de riesgo alto'),
  ('DIF_INVENTARIO_ALERTA', '1', 'Porcentaje académico, no norma oficial'),
  ('DIF_INVENTARIO_CRITICA', '2', 'Porcentaje académico, no norma oficial');

