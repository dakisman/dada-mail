-- This should work well for MySQL ver. 5 - MySQL ver. 4 MAY need some slight modifications. 
-- Some of the modifications include not using the indexes, or rewriting them for MySQL 4.x, specifically

CREATE TABLE IF NOT EXISTS dada_settings (
list                             varchar(16),
setting                          varchar(64),
value                            text
);

CREATE INDEX dada_settings_list_index ON dada_settings (list);

CREATE TABLE IF NOT EXISTS dada_subscribers (
email_id			            int4 not null primary key auto_increment,
email                            text(320),
list                             varchar(16),
list_type                        varchar(64),
list_status                      char(1)
);

-- In very old versions of MySQL (around 4.0), making this table will cause an error, try replacing the line: 
-- email                            text(320),
-- with just: 
-- email                            text,

CREATE INDEX dada_subscribers_all_index ON dada_subscribers (email(320), list, list_type, list_status);

-- Same problem, in very old version of MySQL, this INDEX doesn't seem to work...



CREATE TABLE IF NOT EXISTS dada_profiles ( 
profile_id int4 not null primary key auto_increment,
email                        varchar(320) not null,
password                     text(16),
auth_code                    varchar(64),
update_email_auth_code       varchar(64),
update_email                 varchar(320),
activated                    char(1), 
CONSTRAINT UNIQUE (email)
);

CREATE TABLE IF NOT EXISTS dada_profile_fields (
fields_id int4 not null primary key auto_increment,
email varchar(320) not null,
CONSTRAINT UNIQUE (email)
);

CREATE TABLE IF NOT EXISTS dada_profile_fields_attributes (
	attribute_id int4 not null primary key auto_increment,
	field                       varchar(320),
	label                       varchar(320),
	fallback_value              varchar(320),
-- I haven't made the following, but it seems like a pretty good idea... 
-- sql_col_type              text(16),
-- default                   mediumtext,
-- html_form_widget          varchar(320),
-- required                  char(1),
-- public                    char(1),
	CONSTRAINT UNIQUE (field)
);

CREATE TABLE IF NOT EXISTS dada_archives (
list                          varchar(16),
archive_id                    varchar(32),
subject                       text,
message                       mediumtext,
format                        text,
raw_msg                       mediumtext
);
 
CREATE INDEX dada_archives_list_archive_id_index ON dada_archives (list, archive_id);
 
CREATE TABLE IF NOT EXISTS dada_bounce_scores (
id                            int4 not null primary key auto_increment,
email                         text, 
list                          varchar(16),
score                         int4
); 
 
CREATE TABLE IF NOT EXISTS dada_clickthrough_urls (
url_id  int4 not null primary key auto_increment, 
redirect_id varchar(16), 
msg_id text, 
url text
); 
 
CREATE TABLE IF NOT EXISTS dada_sessions (
     id CHAR(32) NOT NULL PRIMARY KEY,
     a_session TEXT NOT NULL
);