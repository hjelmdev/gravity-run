-- Step 3 of the equipment plan: the host's lobby toggle "Equipment on/off".
-- The setting lives on the room row, is part of the V2 room payload and can only
-- be changed by the owner while the room is OPEN. Changing it bumps the content
-- revision so every player confirms ready again for the new rules. The game
-- client treats a missing `equipment_enabled` field as off, so it keeps working
-- before this migration is applied. The effects themselves are simulated by the
-- clients (RunEffects); the database only stores the choice.

alter table public.multiplayer_rooms
	add column if not exists equipment_enabled boolean not null default false;

-- Same payload as before plus `equipment_enabled`. V1 payloads stay untouched.
create or replace function public._multiplayer_v2_room_payload(p_room_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_payload jsonb;
begin
	v_payload := public._multiplayer_room_payload(p_room_id);
	if v_payload is null then return null; end if;
	select v_payload || jsonb_build_object(
		'roster_revision', r.roster_revision, 'content_revision', r.content_revision,
		'lobby_cycle', r.lobby_cycle, 'state_revision', r.state_revision,
		'equipment_enabled', r.equipment_enabled,
		'members', coalesce((select jsonb_agg(jsonb_build_object(
			'user_id', m.user_id, 'player_slot', m.player_slot, 'display_name', m.display_name,
			'is_ready', m.is_ready, 'ready_cycle', m.ready_cycle,
			'ready_content_revision', m.ready_content_revision,
			'loadout_hash', m.loadout_hash, 'ready_loadout_hash', m.ready_loadout_hash,
			'returned_for_cycle', m.returned_for_cycle,
			'loaded_manifest_hash', m.loaded_manifest_hash, 'skin_id', m.skin_id,
			'is_connected', m.last_seen_at > now() - interval '45 seconds'
		) order by m.player_slot) from public.multiplayer_room_members m where m.room_id = r.room_id), '[]'::jsonb)
	) into v_payload
	from public.multiplayer_rooms r where r.room_id = p_room_id;
	return v_payload;
end $$;

create or replace function public.multiplayer_v2_set_equipment(p_room_id uuid, p_enabled boolean, p_expected_cycle bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	if p_enabled is null then raise exception 'invalid_equipment_setting'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then raise exception 'room_not_found'; end if;
	if v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if v_room.phase <> 'OPEN' then raise exception 'room_not_open'; end if;
	if v_room.lobby_cycle <> p_expected_cycle then raise exception 'stale_lobby_confirmation'; end if;
	if v_room.equipment_enabled = p_enabled then
		return public._multiplayer_v2_room_payload(p_room_id);
	end if;
	update public.multiplayer_rooms set equipment_enabled = p_enabled,
		content_revision = content_revision + 1, state_revision = state_revision + 1,
		last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	update public.multiplayer_room_members set is_ready = false, ready_cycle = 0, ready_content_revision = 0
	where room_id = p_room_id;
	return public._multiplayer_v2_room_payload(p_room_id);
end $$;

revoke all on function public.multiplayer_v2_set_equipment(uuid, boolean, bigint) from public, anon;
grant execute on function public.multiplayer_v2_set_equipment(uuid, boolean, bigint) to authenticated;
