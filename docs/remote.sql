begin;

drop schema if exists remote cascade;

create schema remote

create table table1 ( id serial, name text)

create table table2 ( id serial, name text, updated_on date)
;


insert into remote.table1 (name) values ('aaa'),('bbb'),('ccc');
insert into remote.table2 (name,updated_on) values 
  ('ddd', now()::date - 1 )
,('eee', now()::date - 42)
,('fff', now()::date - 37 );


commit;
select * from remote.table1;
select * from remote.table2;
