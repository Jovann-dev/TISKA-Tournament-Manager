begin;

do $$
declare
  tournament_id text := '__sync_test_' || gen_random_uuid()::text;
  snapshot jsonb := $fixture${
    "competitors": [
      {"id":"c0","data":{"number":"0","name":"Entrant 0"}},
      {"id":"c1","data":{"number":"1","name":"Entrant 1"}},
      {"id":"c2","data":{"number":"2","name":"Entrant 2"}},
      {"id":"c3","data":{"number":"3","name":"Entrant 3"}}
    ],
    "divisions": [
      {"id":"one","data":{"competitionType":"kata","competitorIds":["c0","c1"],"progress":"queued","assignedTatamiName":"Tatami 1","matchRecords":[],"placements":[]}},
      {"id":"two","data":{"competitionType":"kata","competitorIds":["c2","c3"],"progress":"queued","assignedTatamiName":"Tatami 2","matchRecords":[],"placements":[]}}
    ],
    "tatamiDefinitions":[{"name":"Tatami 1","judgesCount":5},{"name":"Tatami 2","judgesCount":5}],
    "tatamiLogs":[]
  }$fixture$::jsonb;
  saved jsonb;
  attempted jsonb;
  rejected boolean;
begin
  saved := public.save_tournament_snapshot(tournament_id, 0, snapshot);
  if (saved->>'revision')::bigint <> 1 then raise exception 'Initial revision failed'; end if;
  if public.save_tournament_snapshot(tournament_id, 0, snapshot) is not null then
    raise exception 'Stale revision was not rejected';
  end if;

  rejected := false;
  begin
    perform public.save_tournament_snapshot(tournament_id, 1,
      jsonb_set(saved, '{divisions,0,data,progress}', '"completed"'));
  exception when raise_exception then rejected := true;
  end;
  if not rejected then raise exception 'Completion without a start was accepted'; end if;

  saved := public.save_tournament_snapshot(tournament_id, 1,
    jsonb_set(saved, '{divisions,0,data,progress}', '"running"'));
  if (saved->>'revision')::bigint <> 2 then raise exception 'Start failed'; end if;

  attempted := jsonb_set(jsonb_set(saved, '{divisions,1,data,progress}', '"running"'),
    '{divisions,1,data,assignedTatamiName}', '"Tatami 1"');
  rejected := false;
  begin
    perform public.save_tournament_snapshot(tournament_id, 2, attempted);
  exception when raise_exception then rejected := true;
  end;
  if not rejected then raise exception 'Tatami occupancy was not enforced'; end if;

  rejected := false;
  begin
    perform public.save_tournament_snapshot(tournament_id, 2,
      jsonb_set(saved, '{competitors,0,data,name}', '"Changed"'));
  exception when raise_exception then rejected := true;
  end;
  if not rejected then raise exception 'Started competitor was not protected'; end if;

  rejected := false;
  begin
    perform public.save_tournament_snapshot(tournament_id, 2,
      jsonb_set(saved, '{divisions,0,data,competitorIds}', '["c1","c0"]'));
  exception when raise_exception then rejected := true;
  end;
  if not rejected then raise exception 'Started bracket was not protected'; end if;

  rejected := false;
  begin
    update public.tournaments set snapshot = saved where id = tournament_id;
  exception when raise_exception then rejected := true;
  end;
  if not rejected then raise exception 'Unversioned write was not rejected'; end if;

  if (select revision from public.tournaments where id = tournament_id) <> 2 then
    raise exception 'Rejected writes changed the revision';
  end if;
  saved := public.save_tournament_snapshot(tournament_id, 2,
    jsonb_set(saved, '{divisions,0,data,progress}', '"queued"'));
  saved := public.save_tournament_snapshot(tournament_id, 3,
    jsonb_set(saved, '{divisions,0,data,competitorIds}', '["c1","c0"]'));
  if (saved->>'revision')::bigint <> 4 then raise exception 'Redo did not unlock bracket'; end if;

  attempted := jsonb_set(saved, '{competitionCategories}',
    '[{"id":"kata","name":"Kata","template":"flagVoting","enabled":true},{"id":"custom","name":"Open Kumite","template":"points","enabled":true}]');
  attempted := jsonb_set(attempted, '{divisions,0,data,competitionCategoryId}', '"custom"');
  attempted := jsonb_set(attempted, '{divisions,0,data,competitionCategoryName}', '"Open Kumite"');
  attempted := jsonb_set(attempted, '{divisions,0,data,competitionTemplate}', '"points"');
  saved := public.save_tournament_snapshot(tournament_id, 4, attempted);
  if (saved->>'revision')::bigint <> 5 then raise exception 'Custom category save failed'; end if;

  rejected := false;
  begin
    perform public.save_tournament_snapshot(tournament_id, 5,
      jsonb_set(saved, '{divisions,0,data,competitionTemplate}', '"flagVoting"'));
  exception when raise_exception then rejected := true;
  end;
  if not rejected then raise exception 'Mismatched category template was accepted'; end if;

  rejected := false;
  begin
    perform public.save_tournament_snapshot(tournament_id, 5,
      jsonb_set(saved, '{competitionCategories}', '[]'));
  exception when raise_exception then rejected := true;
  end;
  if not rejected then raise exception 'Deletion of a used category was accepted'; end if;

  saved := public.save_tournament_snapshot(tournament_id, 5,
    jsonb_set(saved, '{competitionCategories,1,enabled}', 'false'));
  if (saved->>'revision')::bigint <> 6 then raise exception 'Category disable lost existing division'; end if;

  rejected := false;
  begin
    perform public.save_tournament_snapshot(tournament_id, 6, saved - 'competitionCategories');
  exception when raise_exception then rejected := true;
  end;
  if not rejected then raise exception 'An older client dropped the category catalog'; end if;
end;
$$;

rollback;