-- =========================================================
-- 07_queries_examples.sql
-- Example queries demonstrating UniLibPlus usage
-- =========================================================

USE UniLibPlus;

-- ---------------------------------------------------------
-- Q1. List all books with publisher, authors, and subjects
--     (Using vw_book_details view)
-- ---------------------------------------------------------
SELECT
  isbn,
  title,
  pub_year,
  publisher_name,
  authors,
  subjects
FROM vw_book_details
ORDER BY title;

-- ---------------------------------------------------------
-- Q2. Find all books in a specific subject (e.g., 'Computer Science')
-- ---------------------------------------------------------
SELECT
  b.isbn,
  b.title,
  s.name AS subject_name
FROM Book b
JOIN BookSubject bs ON b.isbn = bs.isbn
JOIN Subject s      ON bs.subject_id = s.subject_id
WHERE s.name = 'Computer Science'
ORDER BY b.title;

-- ---------------------------------------------------------
-- Q3. Show where each copy of a given ISBN is located
--     (branch and check-in term) using vw_copy_location
-- ---------------------------------------------------------
SELECT
  copy_id,
  barcode,
  isbn,
  title,
  branch_name,
  checkin_term
FROM vw_copy_location
WHERE isbn = '9780000000001';   -- change ISBN as needed

-- ---------------------------------------------------------
-- Q4. Count number of copies of each book per branch
--     (Using vw_copy_inventory_by_branch)
-- ---------------------------------------------------------
SELECT
  branch_name,
  isbn,
  title,
  num_copies
FROM vw_copy_inventory_by_branch
ORDER BY branch_name, title;

-- ---------------------------------------------------------
-- Q5. List all patrons with their total fines and unpaid fines
--     (Using vw_patron_fines_summary)
-- ---------------------------------------------------------
SELECT
  patron_id,
  first_name,
  last_name,
  email,
  total_fines,
  unpaid_fines
FROM vw_patron_fines_summary
ORDER BY unpaid_fines DESC, last_name, first_name;

-- ---------------------------------------------------------
-- Q6. Show all current loans (not yet returned)
--     (Using vw_current_loans)
-- ---------------------------------------------------------
SELECT
  loan_id,
  copy_id,
  barcode,
  isbn,
  title,
  patron_id,
  patron_name,
  loan_ts,
  due_ts
FROM vw_current_loans
ORDER BY due_ts;

-- ---------------------------------------------------------
-- Q7. Show all overdue loans with patron name
--     (Using vw_overdue_loans)
-- ---------------------------------------------------------
SELECT
  loan_id,
  copy_id,
  barcode,
  isbn,
  title,
  patron_id,
  patron_name,
  loan_ts,
  due_ts
FROM vw_overdue_loans
ORDER BY due_ts;

-- ---------------------------------------------------------
-- Q8. For each patron, list their loans and a computed status
--     (Returned / Overdue / On loan, using vw_patron_loans_with_status)
-- ---------------------------------------------------------
SELECT
  loan_id,
  patron_id,
  patron_name,
  copy_id,
  barcode,
  isbn,
  title,
  loan_ts,
  due_ts,
  return_ts,
  loan_status
FROM vw_patron_loans_with_status
ORDER BY patron_id, loan_ts;

-- ---------------------------------------------------------
-- Q9. Top 5 patrons by number of loans (basic GROUP BY)
-- ---------------------------------------------------------
SELECT
  p.patron_id,
  CONCAT(p.first_name, ' ', p.last_name) AS patron_name,
  COUNT(l.loan_id) AS loan_count
FROM Patron p
LEFT JOIN Loan l ON p.patron_id = l.patron_id
GROUP BY p.patron_id, patron_name
ORDER BY loan_count DESC
LIMIT 5;

-- ---------------------------------------------------------
-- Q10. Most popular books by total number of loans
-- ---------------------------------------------------------
SELECT
  b.isbn,
  b.title,
  COUNT(l.loan_id) AS times_loaned
FROM Book b
JOIN Copy c ON b.isbn = c.isbn
JOIN Loan l ON c.copy_id = l.copy_id
GROUP BY b.isbn, b.title
ORDER BY times_loaned DESC, b.title;

-- ---------------------------------------------------------
-- Q11. Active reservations and their queue (per book and branch)
-- ---------------------------------------------------------
SELECT
  r.reservation_id,
  r.isbn,
  b.title,
  r.branch_id,
  br.name AS branch_name,
  r.patron_id,
  CONCAT(p.first_name, ' ', p.last_name) AS patron_name,
  r.created_at,
  r.status
FROM Reservation r
JOIN Book   b  ON r.isbn      = b.isbn
JOIN Branch br ON r.branch_id = br.branch_id
JOIN Patron p  ON r.patron_id = p.patron_id
WHERE r.status IN ('Active', 'Waiting')
ORDER BY b.title, br.name, r.created_at;

-- ---------------------------------------------------------
-- Q12. E-resource usage summary: sessions and distinct patrons
--     (Using vw_eresource_usage_summary)
-- ---------------------------------------------------------
SELECT
  resource_id,
  title,
  resource_type,
  total_sessions,
  distinct_patrons
FROM vw_eresource_usage_summary
ORDER BY total_sessions DESC, title;

-- ---------------------------------------------------------
-- Q13. Detailed access sessions for a given patron
-- ---------------------------------------------------------
SELECT
  s.session_id,
  s.patron_id,
  CONCAT(p.first_name, ' ', p.last_name) AS patron_name,
  s.resource_id,
  r.title AS resource_title,
  s.start_time,
  s.end_time
FROM AccessSession s
JOIN Patron p    ON s.patron_id   = p.patron_id
JOIN EResource r ON s.resource_id = r.resource_id
WHERE s.patron_id = 1    -- change patron_id as needed
ORDER BY s.start_time;

-- ---------------------------------------------------------
-- Q14. Inter-library loan requests with details
--     (Using vw_illrequest_detail)
-- ---------------------------------------------------------
SELECT
  request_id,
  status,
  requested_at,
  isbn,
  book_title,
  patron_id,
  patron_name,
  partner_id,
  partner_name
FROM vw_illrequest_detail
ORDER BY requested_at DESC;

-- ---------------------------------------------------------
-- Q15. Number of ILL requests by partner library and status
-- ---------------------------------------------------------
SELECT
  pl.partner_id,
  pl.name AS partner_name,
  ir.status,
  COUNT(*) AS num_requests
FROM PartnerLibrary pl
LEFT JOIN ILLRequest ir
  ON pl.partner_id = ir.partner_id
GROUP BY pl.partner_id, partner_name, ir.status
ORDER BY partner_name, ir.status;

-- ---------------------------------------------------------
-- Q16. Example of a subquery:
--     Find patrons who have unpaid fines greater than 10
-- ---------------------------------------------------------
SELECT
  p.patron_id,
  p.first_name,
  p.last_name,
  p.email,
  ps.unpaid_fines
FROM Patron p
JOIN vw_patron_fines_summary ps
  ON p.patron_id = ps.patron_id
WHERE ps.unpaid_fines > 10
ORDER BY ps.unpaid_fines DESC;

-- =========================================================
-- End of 07_queries_examples.sql
-- =========================================================
