create table if not exists sessions (
  id text primary key,
  name text not null,
  phone_number text,
  status text not null default 'AGUARDANDO_QR',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists messages (
  id uuid primary key default gen_random_uuid(),
  session_id text not null references sessions(id),
  direction text not null check (direction in ('in', 'out')),
  contact text not null,
  type text not null check (type in ('text','image','audio','document','video','other')),
  content_ref text,
  status text not null default 'pending',
  sent_at timestamptz,
  received_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists logs (
  id uuid primary key default gen_random_uuid(),
  session_id text not null references sessions(id),
  level text not null,
  event text not null,
  message text,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create table if not exists queue_metrics (
  id uuid primary key default gen_random_uuid(),
  session_id text not null references sessions(id),
  queue_size integer not null default 0,
  processed_count integer not null default 0,
  error_count integer not null default 0,
  captured_at timestamptz not null default now()
);

create index if not exists idx_messages_session on messages(session_id);
create index if not exists idx_logs_session on logs(session_id);
create index if not exists idx_queue_metrics_session on queue_metrics(session_id);

