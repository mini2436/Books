insert into library_sources (name, root_path, enabled, source_type, created_at, updated_at)
select 'sample-nas', 'storage/nas', true, 'WATCHED_FOLDER', now(), now()
where not exists (
    select 1 from library_sources where name = 'sample-nas'
);
