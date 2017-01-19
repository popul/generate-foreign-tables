
-- \ir load_fdws.sql -- not available due to license issue

begin;
drop schema if exists remote_pug_fdw cascade;

create schema if not exists remote_pug_fdw ;

set local search_path to remote_pug_fdw ;

drop server if exists remote_pug_server cascade;
create server remote_pug_server
    foreign data wrapper postgres_fdw
    options ( 
        dbname 'pug_remote'
    );


create user mapping for public server remote_pug_server
options ( password 'password' );

\ir pug_remote_ft.sql

commit;

