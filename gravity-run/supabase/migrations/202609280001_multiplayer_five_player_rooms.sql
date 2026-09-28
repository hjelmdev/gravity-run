-- Expand multiplayer rooms from four to five total players (host + four guests).
alter table public.multiplayer_rooms
	alter column max_players set default 5,
	drop constraint if exists multiplayer_rooms_max_players_check,
	add constraint multiplayer_rooms_max_players_check check (max_players between 2 and 5);

alter table public.multiplayer_room_members
	drop constraint if exists multiplayer_room_members_player_slot_check,
	add constraint multiplayer_room_members_player_slot_check check (player_slot between 1 and 5);

-- Existing open rooms should use the new capacity too, rather than retaining
-- the old four-player value until they expire.
update public.multiplayer_rooms
set max_players = 5
where phase = 'OPEN';
