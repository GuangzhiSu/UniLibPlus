-- =========================================================
-- 02_schema_tables.sql
-- Create all UniLibPlus tables (in FK-safe order)
-- =========================================================

-- Make sure we are in the correct database
USE UniLibPlus;

-- =========================================================
-- 1. Core lookup tables (no foreign keys)
-- =========================================================

-- Address: shared by branches, publishers, patrons, providers, partner libraries
CREATE TABLE Address (
  address_id   INT           PRIMARY KEY,
  street       VARCHAR(120)  NOT NULL,
  city         VARCHAR(80)   NOT NULL,
  state        VARCHAR(40),
  postal_code  VARCHAR(20),
  country      VARCHAR(80)   NOT NULL
);

-- Publisher: publisher of books
CREATE TABLE Publisher (
  publisher_id INT           PRIMARY KEY,
  name         VARCHAR(120)  NOT NULL UNIQUE,
  address_id   INT,
  FOREIGN KEY (address_id) REFERENCES Address(address_id)
);

-- Author: book authors
CREATE TABLE Author (
  author_id   INT          PRIMARY KEY,
  first_name  VARCHAR(80)  NOT NULL,
  last_name   VARCHAR(80)  NOT NULL
);

-- Subject: subject classification for books
CREATE TABLE Subject (
  subject_id INT          PRIMARY KEY,
  name       VARCHAR(80)  NOT NULL UNIQUE
);

-- Term: academic terms used for copy check-in cycles
CREATE TABLE Term (
  term_id    INT          PRIMARY KEY,
  name       VARCHAR(20)  NOT NULL,
  year       INT          NOT NULL,
  start_date DATE,
  end_date   DATE
);

-- FineReason: reasons for fines (late, lost, damaged, etc.)
CREATE TABLE FineReason (
  reason_id    INT           PRIMARY KEY,
  code         VARCHAR(40)   NOT NULL UNIQUE,
  description  VARCHAR(200)
);

-- Provider: e-resource providers / vendors
CREATE TABLE Provider (
  provider_id   INT           PRIMARY KEY,
  name          VARCHAR(120)  NOT NULL UNIQUE,
  contact_email VARCHAR(120),
  address_id    INT,
  FOREIGN KEY (address_id) REFERENCES Address(address_id)
);

-- License: license contracts with providers
CREATE TABLE License (
  license_id       INT    PRIMARY KEY,
  provider_id      INT    NOT NULL,
  start_date       DATE   NOT NULL,
  end_date         DATE   NOT NULL,
  concurrent_limit INT    NOT NULL,
  FOREIGN KEY (provider_id) REFERENCES Provider(provider_id)
);

-- ResourceType: ebook / ejournal / database, etc.
CREATE TABLE ResourceType (
  resource_type_id INT          PRIMARY KEY,
  name             VARCHAR(20)  NOT NULL UNIQUE
);

-- PartnerLibrary: external libraries for inter-library loans
CREATE TABLE PartnerLibrary (
  partner_id INT           PRIMARY KEY,
  name       VARCHAR(150)  NOT NULL UNIQUE,
  address_id INT,
  FOREIGN KEY (address_id) REFERENCES Address(address_id)
);

-- =========================================================
-- 2. Core library entities: Branch, Book, Copy, Patron
-- =========================================================

-- Branch: library branches on campus / off campus
CREATE TABLE Branch (
  branch_id  INT           PRIMARY KEY,
  name       VARCHAR(100)  NOT NULL UNIQUE,
  address_id INT           NOT NULL,
  FOREIGN KEY (address_id) REFERENCES Address(address_id)
);

-- Book: bibliographic records (physical books)
CREATE TABLE Book (
  isbn         CHAR(13)       PRIMARY KEY,
  title        VARCHAR(200)   NOT NULL,
  publisher_id INT,
  pub_year     INT,
  FOREIGN KEY (publisher_id) REFERENCES Publisher(publisher_id),
  CHECK (CHAR_LENGTH(isbn) = 13)
);

-- BookSubject: M:N relationship between Book and Subject
CREATE TABLE BookSubject (
  isbn        CHAR(13)  NOT NULL,
  subject_id  INT       NOT NULL,
  PRIMARY KEY (isbn, subject_id),
  FOREIGN KEY (isbn)       REFERENCES Book(isbn),
  FOREIGN KEY (subject_id) REFERENCES Subject(subject_id)
);

-- BookAuthor: M:N relationship between Book and Author
CREATE TABLE BookAuthor (
  isbn       CHAR(13)  NOT NULL,
  author_id  INT       NOT NULL,
  PRIMARY KEY (isbn, author_id),
  FOREIGN KEY (isbn)      REFERENCES Book(isbn),
  FOREIGN KEY (author_id) REFERENCES Author(author_id)
);

-- Copy: individual physical copies of a book in branches
CREATE TABLE Copy (
  copy_id         INT          PRIMARY KEY,
  isbn            CHAR(13)     NOT NULL,
  branch_id       INT          NOT NULL,
  checkin_term_id INT,
  barcode         VARCHAR(40)  UNIQUE,
  FOREIGN KEY (isbn)            REFERENCES Book(isbn),
  FOREIGN KEY (branch_id)       REFERENCES Branch(branch_id),
  FOREIGN KEY (checkin_term_id) REFERENCES Term(term_id)
);

-- Patron: library users (students, faculty, staff, alumni, etc.)
CREATE TABLE Patron (
  patron_id   INT           PRIMARY KEY,
  first_name  VARCHAR(80)   NOT NULL,
  last_name   VARCHAR(80)   NOT NULL,
  email       VARCHAR(120)  UNIQUE,
  patron_type VARCHAR(20)   NOT NULL,
  address_id  INT,
  balance     DECIMAL(8,2)  NOT NULL DEFAULT 0,
  FOREIGN KEY (address_id) REFERENCES Address(address_id)
);

-- =========================================================
-- 3. Circulation: Loans, Fines, Reservations
-- =========================================================

-- Loan: borrowing transactions
CREATE TABLE Loan (
  loan_id   INT         PRIMARY KEY,
  copy_id   INT         NOT NULL,
  patron_id INT         NOT NULL,
  loan_ts   TIMESTAMP   NOT NULL,
  due_ts    TIMESTAMP   NOT NULL,
  return_ts TIMESTAMP,
  FOREIGN KEY (copy_id)   REFERENCES Copy(copy_id),
  FOREIGN KEY (patron_id) REFERENCES Patron(patron_id)
);

-- Fine: fines charged to patrons for loans
CREATE TABLE Fine (
  fine_id     INT          PRIMARY KEY,
  loan_id     INT          NOT NULL,
  patron_id   INT          NOT NULL,
  reason_id   INT          NOT NULL,
  amount      DECIMAL(8,2) NOT NULL,
  status      VARCHAR(20)  NOT NULL,
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (loan_id)   REFERENCES Loan(loan_id),
  FOREIGN KEY (patron_id) REFERENCES Patron(patron_id),
  FOREIGN KEY (reason_id) REFERENCES FineReason(reason_id)
);

-- Reservation: holds on books at specific branches
CREATE TABLE Reservation (
  reservation_id INT         PRIMARY KEY,
  patron_id      INT         NOT NULL,
  isbn           CHAR(13)    NOT NULL,
  branch_id      INT         NOT NULL,
  created_at     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status         VARCHAR(20) NOT NULL,
  FOREIGN KEY (patron_id) REFERENCES Patron(patron_id),
  FOREIGN KEY (isbn)      REFERENCES Book(isbn),
  FOREIGN KEY (branch_id) REFERENCES Branch(branch_id)
);

-- =========================================================
-- 4. Electronic resources: EResource, AccessSession
-- =========================================================

-- EResource: digital resources licensed by the library
CREATE TABLE EResource (
  resource_id      INT           PRIMARY KEY,
  title            VARCHAR(200)  NOT NULL,
  resource_type_id INT           NOT NULL,
  license_id       INT           NOT NULL,
  FOREIGN KEY (resource_type_id) REFERENCES ResourceType(resource_type_id),
  FOREIGN KEY (license_id)       REFERENCES License(license_id)
);

-- AccessSession: patron access sessions to e-resources
CREATE TABLE AccessSession (
  session_id INT         PRIMARY KEY,
  patron_id  INT         NOT NULL,
  resource_id INT        NOT NULL,
  start_time TIMESTAMP   NOT NULL,
  end_time   TIMESTAMP,
  FOREIGN KEY (patron_id)  REFERENCES Patron(patron_id),
  FOREIGN KEY (resource_id) REFERENCES EResource(resource_id)
);

-- =========================================================
-- 5. Inter-library loan: ILLRequest
-- =========================================================

-- ILLRequest: inter-library loan requests to partner libraries
CREATE TABLE ILLRequest (
  request_id   INT         PRIMARY KEY,
  patron_id    INT         NOT NULL,
  partner_id   INT         NOT NULL,
  isbn         CHAR(13)    NOT NULL,
  status       VARCHAR(20) NOT NULL,
  requested_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (patron_id)  REFERENCES Patron(patron_id),
  FOREIGN KEY (partner_id) REFERENCES PartnerLibrary(partner_id),
  FOREIGN KEY (isbn)       REFERENCES Book(isbn)
);

-- =========================================================
-- End of 02_schema_tables.sql
-- =========================================================
