-- Make the script repeatable: drop the database if it already exists
DROP DATABASE IF EXISTS UniLibPlus;

-- Create the database with UTF8MB4 to fully support Unicode
CREATE DATABASE UniLibPlus
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

-- Switch to the new database
USE UniLibPlus;
