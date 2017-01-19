
    DROP FOREIGN TABLE IF EXISTS "table1";
    CREATE FOREIGN TABLE "table1"
      ("id" integer,
       "name" text)
    SERVER "remote_pug_server"
    OPTIONS (
      schema_name 'remote',
      table_name  'table1'
    );
COMMENT on COLUMN "table1"."id" IS $$remote type: integer$$;
COMMENT on COLUMN "table1"."name" IS $$remote type: text$$;

    DROP FOREIGN TABLE IF EXISTS "table2";
    CREATE FOREIGN TABLE "table2"
      ("id" integer,
       "name" text,
       "updated_on" date)
    SERVER "remote_pug_server"
    OPTIONS (
      schema_name 'remote',
      table_name  'table2'
    );
COMMENT on COLUMN "table2"."id" IS $$remote type: integer$$;
COMMENT on COLUMN "table2"."name" IS $$remote type: text$$;
COMMENT on COLUMN "table2"."updated_on" IS $$remote type: date$$;
