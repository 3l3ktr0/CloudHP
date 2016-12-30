CREATE DATABASE IF NOT EXISTS playstatus;
USE playstatus;
DROP TABLE IF EXISTS customer_status;
CREATE TABLE customer_status(
  id_customer INT(10) unsigned NOT NULL PRIMARY KEY,
  playdate DATETIME NOT NULL
);
