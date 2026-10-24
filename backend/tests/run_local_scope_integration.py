"""PostgreSQL aislado: exporta SOLO esquema y usa exclusivamente datos ficticios.

Desde backend: .venv/Scripts/python.exe tests/run_local_scope_integration.py
Para una suite concreta, añade patrones: test_units.py test_subproduct_editor.py.
No aplica migraciones ni escribe en la conexion habitual del proyecto.
"""
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile

from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

ROOT = Path(__file__).resolve().parents[2]
BIN = Path(os.environ.get('POSTGRES_BIN', 'C:/Program Files/PostgreSQL/18/bin'))
load_dotenv(ROOT / 'backend/.env')
source = make_url(os.environ['DATABASE_URL'])
workspace = ROOT / 'backend/.test_local_scope'
workspace.mkdir(exist_ok=True)
run_dir = Path(tempfile.mkdtemp(prefix='run_', dir=workspace))
flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0


def command(name, args, env=None):
    print('PostgreSQL temporal:', name, flush=True)
    # En Windows el servidor puede heredar pipes del pg_ctl y mantenerlos abiertos.
    log = run_dir / (name + '.log')
    with log.open('w', encoding='utf-8') as output:
        result = subprocess.run([str(BIN / (name + '.exe')), *args],
            env=env, stdout=output, stderr=output, creationflags=flags)
    if result.returncode:
        raise RuntimeError(name + ': ' + log.read_text(encoding='utf-8', errors='replace'))


with socket.socket() as sock:
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
source_env = {**os.environ, 'PGPASSWORD': source.password or '',
              'PGOPTIONS': '-c default_transaction_read_only=on'}
command('pg_dump', ['-h', source.host or 'localhost', '-p', str(source.port or 5432),
    '-U', source.username, '-d', source.database, '--schema-only', '--no-owner',
    '--no-privileges', '-f', str(run_dir / 'schema.sql')], source_env)
command('initdb', ['-D', str(run_dir / 'data'), '-U', 'postgres', '-A', 'trust', '--encoding=UTF8'])
started = False
try:
    command('pg_ctl', ['-D', str(run_dir / 'data'), '-l', str(run_dir / 'server.log'),
        '-o', f'-h 127.0.0.1 -p {port}', '-w', 'start'])
    started = True
    local_env = {k: v for k, v in os.environ.items() if k not in ('PGPASSWORD', 'PGOPTIONS')}
    args = ['-h', '127.0.0.1', '-p', str(port), '-U', 'postgres']
    command('createdb', [*args, 'barbarito_test'], local_env)
    command('psql', [*args, '-d', 'barbarito_test', '-v', 'ON_ERROR_STOP=1',
        '-f', str(run_dir / 'schema.sql')], local_env)
    test_url = f'postgresql://postgres@127.0.0.1:{port}/barbarito_test'
    engine = create_engine(test_url)
    fixture = Path(__file__).with_name('local_scope_fixture.sql').read_text(encoding='utf-8')
    with engine.begin() as c:
        assert c.execute(text('SELECT current_database()')).scalar_one() == 'barbarito_test'
        c.execute(text('DROP TABLE IF EXISTS inventario_asignacion_puesto'))
        c.execute(text('''DO $$ DECLARE tabla text; restriccion record; BEGIN
                    FOREACH tabla IN ARRAY ARRAY['producto','subproducto','presentacion_venta',
                        'subproducto_detalle','receta_detalle','grupo_salsa_opcion'] LOOP
                        FOR restriccion IN SELECT conname FROM pg_constraint
                            WHERE conrelid=format('public.%I',tabla)::regclass
                            AND (conname='fk_'||tabla||'_unidad_medida' OR
                                (contype='c' AND pg_get_constraintdef(oid) ILIKE '%unidad%')) LOOP
                            EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I',tabla,restriccion.conname);
                        END LOOP;
                    END LOOP;
                END $$'''))
        c.execute(text('DROP TABLE IF EXISTS unidad_medida CASCADE'))
        # La copia contiene SOLO esquema, sin datos reales. Reproducir aquí el
        # estado anterior permite verificar también la migración del nuevo libro.
        if c.execute(text("SELECT to_regclass('public.inventario_evento')")).scalar():
            c.execute(text('''
                DROP TRIGGER IF EXISTS movimiento_evento ON movimiento_inventario_detalle;
                DROP TRIGGER IF EXISTS recepcion_evento ON factura_recepcion_detalle;
                DROP TRIGGER IF EXISTS cobro_jornada ON salon_cobro;
                ALTER TABLE salon_cobro DROP COLUMN id_jornada;
                DROP TABLE inventario_conteo_historial,inventario_conteo,inventario_ronda,
                  inventario_evento,inventario_jornada_inicio,inventario_jornada,inventario_saldo_inicial CASCADE;
                DROP FUNCTION inventario_registrar_evento(),inventario_cobro_jornada(),inventario_abrir_jornada(integer,integer,date);
            '''))
        # Si el proyecto ya aplico 03, reproducir el estado previo SOLO en esta
        # base vacia de pruebas, para seguir ensayando la migracion con fixtures.
        if c.execute(text("SELECT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='uq_inventario_local_fecha')")).scalar():
            c.execute(text('''
                ALTER TABLE inventario_cierre DROP CONSTRAINT uq_inventario_local_fecha;
                ALTER TABLE inventario_cierre ADD CONSTRAINT inventario_cierre_fecha_inventario_key UNIQUE(fecha_inventario);
                ALTER TABLE inventario_cierre ALTER COLUMN id_local DROP NOT NULL;
                ALTER TABLE orden_compra ALTER COLUMN id_local DROP NOT NULL;
                ALTER TABLE movimiento_inventario ALTER COLUMN id_local DROP NOT NULL;
                ALTER TABLE orden_compra_detalle ALTER COLUMN id_proveedor DROP NOT NULL;
                CREATE INDEX ix_inventario_local_fecha ON inventario_cierre(id_local,fecha_inventario);
            '''))
        c.execute(text(fixture))
    # La version actual de la base de origen debe contener las etapas 01 y 02.
    migration = (ROOT / 'database/normalizacion/03_activar_locales_TRAS_ADAPTAR_BACKEND.sql').read_text(encoding='utf-8')
    migration = migration.replace("current_database() <> 'barbarito'", "current_database() <> 'barbarito_test'")
    migration = migration.replace('confirmacion_locales VALUES (false)', 'confirmacion_locales VALUES (true)')
    with engine.connect() as c:
        c.execute(text(migration))
    with engine.connect() as c:
        if not c.execute(text("SELECT to_regclass('public.movimiento_seguimiento')")).scalar():
            tracking = (ROOT / 'database/migrations/20260922_seguimiento_movimientos.sql').read_text(encoding='utf-8')
            c.execute(text(tracking.replace("current_database() <> 'barbarito'", "current_database() <> 'barbarito_test'")))
    with engine.connect() as c:
        if not c.execute(text("SELECT to_regclass('public.usuario_pin_salon')")).scalar():
            salon = (ROOT / 'database/migrations/20260923_acceso_salon.sql').read_text(encoding='utf-8')
            c.execute(text(salon.replace("current_database()<>'barbarito'", "current_database()<>'barbarito_test'")))
    with engine.connect() as c:
        if not c.execute(text("SELECT to_regclass('public.salon_pedido')")).scalar():
            pedidos = (ROOT / 'database/migrations/20260923_pedidos_salon.sql').read_text(encoding='utf-8')
            c.execute(text(pedidos.replace("current_database()<>'barbarito'", "current_database()<>'barbarito_test'")))
    with engine.connect() as c:
        if not c.execute(text("SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='salon_pedido' AND column_name='envio_clave')")).scalar():
            envios = (ROOT / 'database/migrations/20260923_envios_adicionales_salon.sql').read_text(encoding='utf-8')
            c.execute(text(envios.replace("current_database()<>'barbarito'", "current_database()<>'barbarito_test'")))
    with engine.connect() as c:
        if not c.execute(text("SELECT to_regclass('public.salon_distribucion')")).scalar():
            layout = (ROOT / 'database/migrations/20260923_distribucion_salon.sql').read_text(encoding='utf-8')
            c.execute(text(layout.replace("current_database()<>'barbarito'", "current_database()<>'barbarito_test'")))
    with engine.connect() as c:
        if not c.execute(text("SELECT to_regclass('public.salon_pedido_actual')")).scalar():
            control = (ROOT / 'database/migrations/20260923_control_salon.sql').read_text(encoding='utf-8')
            c.execute(text(control.replace("current_database()<>'barbarito'", "current_database()<>'barbarito_test'")))
    with engine.connect() as c:
        if not c.execute(text("SELECT to_regclass('public.asistente_ia_borrador')")).scalar():
            assistant = (ROOT / 'database/migrations/20260923_asistente_ia.sql').read_text(encoding='utf-8')
            c.execute(text(assistant.replace("current_database()<>'barbarito'", "current_database()<>'barbarito_test'")))
    with engine.connect() as c:
        if not c.execute(text("SELECT to_regclass('public.salon_cobro')")).scalar():
            pagos = (ROOT / 'database/migrations/20260926_pagos_salon.sql').read_text(encoding='utf-8')
            c.execute(text(pagos.replace("current_database()<>'barbarito'", "current_database()<>'barbarito_test'")))
    with engine.connect() as c:
        if not c.execute(text("SELECT to_regclass('public.promocion_reposicion')")).scalar():
            promociones = (ROOT / 'database/migrations/20261016_promociones_reposicion_salon.sql').read_text(encoding='utf-8')
            c.execute(text(promociones.replace("current_database()<>'barbarito'", "current_database()<>'barbarito_test'")))
    engine.dispose()
    env = {**local_env, 'DATABASE_URL': test_url, 'LOCAL_SCOPE_TEST_DB': '1'}
    patterns = sys.argv[1:]
    test_command = [sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-v']
    if patterns:
        test_command = [sys.executable, '-c',
            "import sys,unittest; suite=unittest.TestSuite(); "
            "[suite.addTests(unittest.TestLoader().discover('tests',pattern=p)) for p in sys.argv[1:]]; "
            "result=unittest.TextTestRunner(verbosity=2).run(suite); sys.exit(not result.wasSuccessful())",
            *patterns]
    result = subprocess.run(test_command,
        cwd=ROOT / 'backend', env=env, creationflags=flags, capture_output=True, text=True)
    print(result.stdout + result.stderr, flush=True)
    (run_dir / 'tests.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError('Fallo la suite de pruebas en PostgreSQL temporal')
    if patterns:
        print('Pruebas seleccionadas completadas en PostgreSQL temporal. Ningun dato real fue modificado.')
        sys.exit(0)
    with engine.begin() as c:
        assert c.execute(text('SELECT current_database()')).scalar_one() == 'barbarito_test'
        c.execute(text("INSERT INTO perfiles(id_perfil,nombre,descripcion) VALUES(3,'Supervisor','Prueba'),(4,'Miembro','Prueba') ON CONFLICT DO NOTHING"))
    with engine.connect() as c:
        migration = (ROOT / 'database/migrations/20260926_jornadas_conteos.sql').read_text(encoding='utf-8')
        c.execute(text(migration.replace("current_database()<>'barbarito'", "current_database()<>'barbarito_test'")))
    env['OPERATIONAL_TEST_DB']='1'
    result = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_inventory_operations.py', '-v'],
        cwd=ROOT / 'backend', env=env, creationflags=flags, capture_output=True, text=True)
    print(result.stdout + result.stderr, flush=True)
    (run_dir / 'operations.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError('Fallo la suite de jornadas y conteos en PostgreSQL temporal')
    with engine.connect() as c:
        migration = (ROOT / 'database/migrations/20260928_asignacion_conteos_puestos.sql').read_text(encoding='utf-8')
        c.execute(text(migration.replace("current_database()<>'barbarito'", "current_database()<>'barbarito_test'")))
    env['POSITION_COUNTS_TEST_DB']='1'
    result = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_count_positions.py', '-v'],
        cwd=ROOT / 'backend', env=env, creationflags=flags, capture_output=True, text=True)
    print(result.stdout + result.stderr, flush=True)
    (run_dir / 'positions.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError('Fallo la suite de asignación permanente por puestos')
    result = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_inventory_assistant.py', '-v'],
        cwd=ROOT / 'backend', env=env, creationflags=flags, capture_output=True, text=True)
    print(result.stdout + result.stderr, flush=True)
    (run_dir / 'inventory_assistant.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError('Fallo la suite del agente de inventario')
    print('Pruebas completadas en base temporal. Ningun registro real fue copiado o modificado.')
finally:
    if started:
        command('pg_ctl', ['-D', str(run_dir / 'data'), '-m', 'fast', '-w', 'stop'])
