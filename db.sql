CREATE TABLE dub_package (
    id SERIAL,
    name TEXT NOT NULL,
    url_name TEXT NOT NULL,
    description TEXT NOT NULL,
    adrdox_cmdline_options TEXT NOT NULL,
    parent_id INTEGER NULL, -- for subpackages

    -- FIXME: adjustment score?

    PRIMARY KEY(id)
);
CREATE INDEX dub_packages_by_name ON dub_package(name);

CREATE TABLE package_version (
    id SERIAL,
    dub_package_id INTEGER NOT NULL,
    version_tag TEXT NOT NULL,
    release_date TIMESTAMPTZ,
    is_latest BOOLEAN NOT NULL,

    FOREIGN KEY(dub_package_id) REFERENCES dub_package(id) ON DELETE CASCADE ON UPDATE CASCADE,

    PRIMARY KEY(id)
);

CREATE TABLE d_symbols (
    id SERIAL,
    package_version_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    nesting_level INTEGER NOT NULL, -- 0 for module, 1 for top level in module, etc
    module_name TEXT NOT NULL,
    fully_qualified_name TEXT NOT NULL,
    url_name TEXT NOT NULL, -- can have a .1 and/or # in it btw. but should not have .html.
    summary TEXT NOT NULL,

    FOREIGN KEY(package_version_id) REFERENCES package_version(id) ON DELETE CASCADE ON UPDATE CASCADE,

    PRIMARY KEY(id)
);
CREATE INDEX d_symbols_by_name ON d_symbols(name);
CREATE INDEX d_symbols_by_fqn ON d_symbols(fully_qualified_name);

CREATE TABLE auto_generated_tags (
    id SERIAL,
    tag TEXT NOT NULL,
    d_symbols_id INTEGER NOT NULL,
    score INTEGER NOT NULL,
    package_version_id INTEGER NOT NULL,

    FOREIGN KEY(d_symbols_id) REFERENCES d_symbols(id) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY(package_version_id) REFERENCES package_version(id) ON DELETE CASCADE ON UPDATE CASCADE,

    PRIMARY KEY(id)
);
CREATE INDEX auto_generated_tags_by_tag ON auto_generated_tags(tag);

CREATE TABLE hand_written_tags (
    id SERIAL,
    tag TEXT NOT NULL,
    d_symbol_fully_qualified_name TEXT NOT NULL,
    score INTEGER NOT NULL,

    PRIMARY KEY(id)
);
CREATE INDEX hand_written_tags_by_tag ON hand_written_tags(tag);

CREATE TABLE adrdox_schema (
    schema_version INTEGER NOT NULL
);

INSERT INTO adrdox_schema VALUES (1);
