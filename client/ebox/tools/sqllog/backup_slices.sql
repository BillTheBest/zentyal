CREATE TABLE backup_slices(
        tablename VARCHAR(40) NOT NULL,
        id BIGINT NOT NULL,
        beginTs TIMESTAMP NOT NULL,
        endTs TIMESTAMP NOT NULL,
        archived BOOLEAN DEFAULT FALSE,
        timeline INT NOT NULL
);

CREATE UNIQUE INDEX backup_slices_i  ON backup_slices (id, tablename, timeline);