CREATE TABLE IF NOT EXISTS samba_virus_report (
    date DATE,
    client CHAR(15), -- FIXME INET
    virus BIGINT
);
