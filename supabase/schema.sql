-- Estrutura do banco do Extrato Bybit.
--
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em Run.
-- Pode rodar mais de uma vez: tudo aqui é idempotente.
--
-- O que NÃO entra neste banco, de propósito: a API Key e o Secret da Bybit.
-- Eles dão acesso de leitura à conta inteira, então ficam apenas no cofre de
-- cada aparelho. Um vazamento daqui não vira acesso à sua conta da exchange.

-- ---------------------------------------------------------------------------
-- Preferências: ajustes, metas, planejamento e gastos ocultos
-- ---------------------------------------------------------------------------
-- Guardado como chave/valor porque o formato de cada ajuste muda com o tempo;
-- assim uma mudança no app não exige migração de tabela.

create table if not exists public.preferencias (
  user_id       uuid        not null references auth.users (id) on delete cascade,
  chave         text        not null,
  valor         jsonb       not null,
  atualizado_em timestamptz not null default now(),
  primary key (user_id, chave)
);

comment on table public.preferencias is
  'Ajustes do usuário: categorias corrigidas, apelidos, ocultos, metas.';

-- ---------------------------------------------------------------------------
-- Transações: o arquivo histórico
-- ---------------------------------------------------------------------------
-- A Bybit mantém só uns seis meses no histórico de recompensas. Esta tabela é
-- a memória longa: o que passou por aqui uma vez não se perde mais, e vale
-- para todos os aparelhos.

create table if not exists public.transacoes (
  user_id       uuid        not null references auth.users (id) on delete cascade,
  id_lancamento text        not null,
  ocorrido_em   timestamptz not null,
  dados         jsonb       not null,
  atualizado_em timestamptz not null default now(),
  primary key (user_id, id_lancamento)
);

comment on table public.transacoes is
  'Arquivo de lançamentos, para não depender da janela curta da API da Bybit.';

-- Ordenar por data é a consulta mais comum do app.
create index if not exists transacoes_por_data
  on public.transacoes (user_id, ocorrido_em desc);

-- ---------------------------------------------------------------------------
-- Segurança por linha
-- ---------------------------------------------------------------------------
-- Sem isto, a chave pública que vai no app daria acesso aos dados de todos.
-- Com isto, o próprio banco garante que cada um só enxerga o que é seu —
-- não depende do app se comportar bem.

alter table public.preferencias enable row level security;
alter table public.transacoes  enable row level security;

drop policy if exists "dono cuida das proprias preferencias" on public.preferencias;
create policy "dono cuida das proprias preferencias"
  on public.preferencias
  for all
  to authenticated
  using      (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "dono cuida das proprias transacoes" on public.transacoes;
create policy "dono cuida das proprias transacoes"
  on public.transacoes
  for all
  to authenticated
  using      (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Carimbo de atualização
-- ---------------------------------------------------------------------------
-- Mantido pelo banco, e não pelo app: assim vale mesmo se algum aparelho
-- estiver com o relógio errado — o que já vimos acontecer com a Bybit.

create or replace function public.marca_atualizacao()
returns trigger
language plpgsql
as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$;

drop trigger if exists preferencias_atualizado_em on public.preferencias;
create trigger preferencias_atualizado_em
  before update on public.preferencias
  for each row execute function public.marca_atualizacao();

drop trigger if exists transacoes_atualizado_em on public.transacoes;
create trigger transacoes_atualizado_em
  before update on public.transacoes
  for each row execute function public.marca_atualizacao();
