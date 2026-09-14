PRAGMA application_id = 1146375251;
PRAGMA user_version = 1;
CREATE TABLE localization (
    resource TEXT NOT NULL,
    hash TEXT NOT NULL,
    /*COLUMNS*/,
    PRIMARY KEY (resource, hash)
);
CREATE INDEX localization_hash ON localization(hash);
CREATE TABLE key_names (
    hash TEXT NOT NULL,
    key TEXT NOT NULL,
    PRIMARY KEY (hash, key)
);
CREATE TABLE metadata (info TEXT NOT NULL);
