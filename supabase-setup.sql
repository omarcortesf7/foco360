-- Foco 360 · ranking compartido por grupo
-- Pegar entero en Supabase > SQL Editor > Run. Se puede ejecutar más de una vez.

create table if not exists public.fk_best (
  group_code  text not null,
  player_id   text not null,
  player_name text not null,
  exercise    text not null,
  value       numeric not null,
  unit        text not null,
  better      text not null check (better in ('lower','higher')),
  accuracy    numeric,
  meta        text,
  updated_at  timestamptz not null default now(),
  primary key (group_code, player_id, exercise)
);

-- Todos pueden LEER el ranking; nadie puede escribir directo en la tabla.
alter table public.fk_best enable row level security;
drop policy if exists "fk_best_read" on public.fk_best;
create policy "fk_best_read" on public.fk_best for select using (true);

-- La única forma de escribir es esta función, que solo guarda la marca si
-- mejora la que ya había (mejor tiempo = menor, mejor precisión = mayor).
create or replace function public.fk_submit(
  p_group    text,
  p_player   text,
  p_name     text,
  p_exercise text,
  p_value    numeric,
  p_unit     text,
  p_better   text,
  p_accuracy numeric,
  p_meta     text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_exercise not in ('schulte','peripheral','speed','cpt','reaction','stroop','choice','flash','calc') then
    raise exception 'ejercicio no valido';
  end if;
  if p_better not in ('lower','higher') or p_unit not in ('ms','%') then
    raise exception 'dato no valido';
  end if;
  if p_group !~ '^[a-z0-9_-]{1,40}$' or length(p_player) > 40
     or length(btrim(p_name)) = 0 or length(p_name) > 24 then
    raise exception 'dato no valido';
  end if;
  if p_value is null or p_value < 0 or p_value > 3600000
     or (p_unit = '%' and p_value > 100) then
    raise exception 'valor no valido';
  end if;

  insert into public.fk_best
    (group_code, player_id, player_name, exercise, value, unit, better, accuracy, meta)
  values
    (p_group, p_player, btrim(p_name), p_exercise, p_value, p_unit, p_better,
     p_accuracy, left(coalesce(p_meta, ''), 60))
  on conflict (group_code, player_id, exercise) do update
    set player_name = excluded.player_name,
        value       = excluded.value,
        unit        = excluded.unit,
        better      = excluded.better,
        accuracy    = excluded.accuracy,
        meta        = excluded.meta,
        updated_at  = now()
    where (public.fk_best.better = 'lower'  and excluded.value < public.fk_best.value)
       or (public.fk_best.better = 'higher' and excluded.value > public.fk_best.value);

  -- si no mejoró la marca, al menos mantener el nombre al día
  update public.fk_best
     set player_name = btrim(p_name)
   where group_code = p_group and player_id = p_player and exercise = p_exercise
     and player_name <> btrim(p_name);
end;
$$;

revoke all on function public.fk_submit(text,text,text,text,numeric,text,text,numeric,text) from public;
grant execute on function public.fk_submit(text,text,text,text,numeric,text,text,numeric,text) to anon, authenticated;
grant select on public.fk_best to anon, authenticated;
