import { $Database, $Env, OpenApiExtension, PocketUIExtension, teenyHono } from 'teenybase/worker';
import config from '../migrations/config.json';
import { DatabaseSettings } from "teenybase";

export interface Env {
  Bindings: $Env['Bindings'] & {
    PRIMARY_DB: D1Database;
    PRIMARY_R2?: R2Bucket;
  },
  Variables: $Env['Variables']
}

const app = teenyHono<Env>(async (c)=> {
  const db = new $Database(c, config as unknown as DatabaseSettings, c.env.PRIMARY_DB, c.env.PRIMARY_R2)
  db.extensions.push(new OpenApiExtension(db, true))
  db.extensions.push(new PocketUIExtension(db))

  return db
}, undefined, {
  logger: false,
  cors: true,
})

app.get('/', (c)=>{
  return c.json({message: 'Hello Hono'})
})

app.get('/api/counter', async (c) => {
  const db = c.env.PRIMARY_DB
  const row = await db.prepare('SELECT * FROM counter WHERE id = 1').first()
  if (!row) {
    return c.json({ walks: 0, distance_km: 0, meditation_min: 0, talk_min: 0, last_walk_at: null })
  }
  return c.json(row, 200, {
    'Cache-Control': 'public, max-age=10800',
  })
})

app.post('/api/counter', async (c) => {
  const token = c.req.header('X-Device-Token')
  if (!token || token.length < 8) {
    return c.json({ error: 'missing token' }, 401)
  }

  const db = c.env.PRIMARY_DB

  const recent = await db.prepare(
    'SELECT 1 FROM counter_rate_limit WHERE token = ? AND created_at > datetime(\'now\', \'-1 hour\')'
  ).bind(token).first()
  if (recent) {
    return c.json({ error: 'rate limited' }, 429)
  }

  const body = await c.req.json<{
    walks?: number
    distance_km?: number
    meditation_min?: number
    talk_min?: number
  }>()

  const walks = Math.max(0, Math.floor(body.walks ?? 0))
  const distanceKm = Math.max(0, body.distance_km ?? 0)
  const meditationMin = Math.max(0, Math.floor(body.meditation_min ?? 0))
  const talkMin = Math.max(0, Math.floor(body.talk_min ?? 0))

  if (walks === 0 && distanceKm === 0) {
    return c.json({ error: 'nothing to count' }, 400)
  }

  await db.batch([
    db.prepare(
      `UPDATE counter SET
        total_walks = total_walks + ?,
        total_distance_km = total_distance_km + ?,
        total_meditation_min = total_meditation_min + ?,
        total_talk_min = total_talk_min + ?,
        last_walk_at = datetime('now')
      WHERE id = 1`
    ).bind(walks, distanceKm, meditationMin, talkMin),
    db.prepare(
      'INSERT INTO counter_rate_limit (token, created_at) VALUES (?, datetime(\'now\'))'
    ).bind(token),
    db.prepare(
      'DELETE FROM counter_rate_limit WHERE created_at < datetime(\'now\', \'-2 hours\')'
    ),
  ])

  return c.json({ ok: true }, 204)
})

export default app
