# Control de Milanesas

App móvil para controlar producción y salidas de milanesas, con **login por usuario**
y **datos compartidos por equipo**: todos ven todo lo cargado, con **quién lo cargó** y **cuándo**.

## Archivos
- `index.html` — la app completa (usa supabase-js por CDN).
- `config.js` — pegás tu `SUPABASE_URL` y `SUPABASE_ANON_KEY`.
- `schema.sql` — crea las tablas + seguridad (RLS compartido) + perfiles de personas.
- `vercel.json`, `.gitignore`.

## Puesta en marcha (resumen)
1. Crear proyecto en **Supabase** (región South America / São Paulo).
2. **SQL Editor** → pegar y correr **todo** `schema.sql`.
3. **Settings → API** → copiar *Project URL* y *anon key* → pegarlas en `config.js`.
4. Subir a **Vercel** (desde GitHub o con `vercel` CLI).
5. Entrar a la URL, **crear tu cuenta con tu nombre** e ingresar.

La guía detallada, paso a paso, está en el documento aparte que te pasó Claude.

## Cómo funciona la compartición
- Toda la data (carnes, tamaños, locales, productos, producciones, salidas) es del **equipo**.
- La seguridad es por RLS: **con sesión iniciada** ves y cargás todo; **sin sesión**, nada.
- Cada alta guarda `creado_por` (quién) y `created_at` (cuándo). En Historial y en
  Configuración se muestra el autor y la fecha. La pantalla **Config → Personas** lista
  a todos los que usan la app.

## Modo demo
Si `config.js` queda con los valores `TU-...`, la app abre en **modo demo** con datos de
ejemplo (no se guardan). Sirve para ver el diseño sin conectar Supabase.

## Modelo de datos
- `profiles` {id, nombre, email} — una fila por persona.
- `carnes` {name, receta jsonb} · `tamanos` {name} · `locales` {name} · `productos` {name, unit}
- `producciones` {fecha, carne_id, tam_id, kg, mila, items jsonb}
- `salidas` {fecha, local_id, carne_id, mila, nota}
- Todas con `created_at` y `creado_por`.
