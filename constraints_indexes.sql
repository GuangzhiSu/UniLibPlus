-- =========================================================
-- 03_constraints_indexes.sql
-- Additional indexes for UniLibPlus schema
-- (Run after 02_schema_tables.sql)
-- =========================================================

USE UniLibPlus;

-- =========================================================
-- 1. Book-related indexes
-- =========================================================

-- Support searching books by title (e.g., partial matches, ordering)
CREATE INDEX idx_book_title
  ON Book (title);

-- Support filtering and sorting books by publication year
CREATE INDEX idx_book_pub_year
  ON Book (pub_year);

-- =========================================================
-- 2. Term indexes
-- =========================================================

-- Support queries like: find all terms for a given year and name
CREATE INDEX idx_term_year_name
  ON Term (year, name);

-- =========================================================
-- 3. Copy / inventory indexes
-- =========================================================

-- Support branch-level inventory queries:
--   - How many copies of a specific book at a branch?
--   - List all copies of a book in a branch.
CREATE INDEX idx_copy_branch_isbn
  ON Copy (branch_id, isbn);

-- =========================================================
-- 4. Patron indexes
-- =========================================================

-- Support name-based patron searches (e.g., by last name then first name)
CREATE INDEX idx_patron_name
  ON Patron (last_name, first_name);

-- =========================================================
-- 5. Circulation: Loan, Fine, Reservation
-- =========================================================

-- Loan: find loans per patron and track due dates (e.g., overdue items)
CREATE INDEX idx_loan_patron_due
  ON Loan (patron_id, due_ts);

-- Loan: find all loans for a given copy ordered by time
CREATE INDEX idx_loan_copy_loants
  ON Loan (copy_id, loan_ts);

-- Fine: list fines per patron and group by status (Paid / Unpaid / Pending)
CREATE INDEX idx_fine_patron_status
  ON Fine (patron_id, status);

-- Reservation: typical query is "what active reservations does this patron have?"
CREATE INDEX idx_reservation_patron_status
  ON Reservation (patron_id, status);

-- =========================================================
-- 6. E-resources and access sessions
-- =========================================================

-- EResource: support queries by resource type and license
CREATE INDEX idx_eresource_type_license
  ON EResource (resource_type_id, license_id);

-- AccessSession: reporting usage per patron over time
CREATE INDEX idx_accesssession_patron_start
  ON AccessSession (patron_id, start_time);

-- =========================================================
-- 7. Inter-library loan
-- =========================================================

-- ILLRequest: typical queries:
--   - list all requests by a patron
--   - filter by status (Requested/Shipped/Received/Completed/Cancelled)
CREATE INDEX idx_illrequest_patron_status
  ON ILLRequest (patron_id, status);

-- =========================================================
-- End of 03_constraints_indexes.sql
-- =========================================================
