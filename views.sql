-- =========================================================
-- 06_views.sql
-- Commonly used views for UniLibPlus
-- (Run after 02_schema_tables.sql and optionally after data inserts)
-- =========================================================

USE UniLibPlus;

-- ---------------------------------------------------------
-- 1. Book details: publisher + authors + subjects
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_book_details AS
SELECT
  b.isbn,
  b.title,
  b.pub_year,
  p.name AS publisher_name,
  GROUP_CONCAT(DISTINCT CONCAT(a.first_name, ' ', a.last_name)
               ORDER BY a.last_name, a.first_name SEPARATOR ', ') AS authors,
  GROUP_CONCAT(DISTINCT s.name ORDER BY s.name SEPARATOR ', ') AS subjects
FROM Book b
LEFT JOIN Publisher p     ON b.publisher_id = p.publisher_id
LEFT JOIN BookAuthor ba   ON b.isbn = ba.isbn
LEFT JOIN Author a        ON ba.author_id = a.author_id
LEFT JOIN BookSubject bs  ON b.isbn = bs.isbn
LEFT JOIN Subject s       ON bs.subject_id = s.subject_id
GROUP BY
  b.isbn,
  b.title,
  b.pub_year,
  p.name;

-- ---------------------------------------------------------
-- 2. Copy location: where each copy lives
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_copy_location AS
SELECT
  c.copy_id,
  c.barcode,
  c.isbn,
  b.title,
  br.branch_id,
  br.name          AS branch_name,
  t.term_id        AS checkin_term_id,
  CONCAT(t.name, ' ', t.year) AS checkin_term
FROM Copy c
JOIN Book   b ON c.isbn = b.isbn
JOIN Branch br ON c.branch_id = br.branch_id
LEFT JOIN Term t ON c.checkin_term_id = t.term_id;

-- ---------------------------------------------------------
-- 3. Patron contact info + basic type
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_patron_contact AS
SELECT
  p.patron_id,
  p.first_name,
  p.last_name,
  p.email,
  p.patron_type,
  p.balance,
  a.city,
  a.state,
  a.country
FROM Patron p
LEFT JOIN Address a ON p.address_id = a.address_id;

-- ---------------------------------------------------------
-- 4. Patron fines summary (total and unpaid)
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_patron_fines_summary AS
SELECT
  p.patron_id,
  p.first_name,
  p.last_name,
  p.email,
  COALESCE(SUM(f.amount), 0) AS total_fines,
  COALESCE(SUM(CASE WHEN f.status = 'Unpaid' THEN f.amount ELSE 0 END), 0) AS unpaid_fines
FROM Patron p
LEFT JOIN Fine f
  ON p.patron_id = f.patron_id
GROUP BY
  p.patron_id,
  p.first_name,
  p.last_name,
  p.email;

-- ---------------------------------------------------------
-- 5. Current loans (not yet returned)
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_current_loans AS
SELECT
  l.loan_id,
  l.copy_id,
  c.barcode,
  b.isbn,
  b.title,
  l.patron_id,
  CONCAT(p.first_name, ' ', p.last_name) AS patron_name,
  l.loan_ts,
  l.due_ts
FROM Loan l
JOIN Copy c   ON l.copy_id = c.copy_id
JOIN Book b   ON c.isbn = b.isbn
JOIN Patron p ON l.patron_id = p.patron_id
WHERE l.return_ts IS NULL;

-- ---------------------------------------------------------
-- 6. Overdue loans (due date passed and not returned)
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_overdue_loans AS
SELECT
  l.loan_id,
  l.copy_id,
  c.barcode,
  b.isbn,
  b.title,
  l.patron_id,
  CONCAT(p.first_name, ' ', p.last_name) AS patron_name,
  l.loan_ts,
  l.due_ts
FROM Loan l
JOIN Copy c   ON l.copy_id = c.copy_id
JOIN Book b   ON c.isbn = b.isbn
JOIN Patron p ON l.patron_id = p.patron_id
WHERE l.return_ts IS NULL
  AND l.due_ts < NOW();

-- ---------------------------------------------------------
-- 7. Patron loans with computed loan status
--    (Returned / Overdue / On loan)
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_patron_loans_with_status AS
SELECT
  l.loan_id,
  l.patron_id,
  CONCAT(p.first_name, ' ', p.last_name) AS patron_name,
  l.copy_id,
  c.barcode,
  b.isbn,
  b.title,
  l.loan_ts,
  l.due_ts,
  l.return_ts,
  CASE
    WHEN l.return_ts IS NOT NULL THEN 'Returned'
    WHEN l.due_ts < NOW() THEN 'Overdue'
    ELSE 'On loan'
  END AS loan_status
FROM Loan l
JOIN Patron p ON l.patron_id = p.patron_id
JOIN Copy   c ON l.copy_id = c.copy_id
JOIN Book   b ON c.isbn = b.isbn;

-- ---------------------------------------------------------
-- 8. Copy inventory by branch and book
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_copy_inventory_by_branch AS
SELECT
  br.branch_id,
  br.name AS branch_name,
  c.isbn,
  b.title,
  COUNT(*) AS num_copies
FROM Copy c
JOIN Branch br ON c.branch_id = br.branch_id
JOIN Book   b  ON c.isbn = b.isbn
GROUP BY
  br.branch_id,
  br.name,
  c.isbn,
  b.title;

-- ---------------------------------------------------------
-- 9. E-resource usage summary
--    (sessions and distinct users per resource)
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_eresource_usage_summary AS
SELECT
  r.resource_id,
  r.title,
  rt.name AS resource_type,
  COUNT(s.session_id) AS total_sessions,
  COUNT(DISTINCT s.patron_id) AS distinct_patrons
FROM EResource r
JOIN ResourceType rt ON r.resource_type_id = rt.resource_type_id
LEFT JOIN AccessSession s ON r.resource_id = s.resource_id
GROUP BY
  r.resource_id,
  r.title,
  rt.name;

-- ---------------------------------------------------------
-- 10. Detailed inter-library loan requests
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_illrequest_detail AS
SELECT
  ir.request_id,
  ir.status,
  ir.requested_at,
  ir.isbn,
  b.title AS book_title,
  ir.patron_id,
  CONCAT(p.first_name, ' ', p.last_name) AS patron_name,
  ir.partner_id,
  pl.name AS partner_name
FROM ILLRequest ir
JOIN Patron        p  ON ir.patron_id  = p.patron_id
JOIN PartnerLibrary pl ON ir.partner_id = pl.partner_id
JOIN Book          b  ON ir.isbn       = b.isbn;

-- =========================================================
-- End of 06_views.sql
-- =========================================================
