-- =========================================================
-- 07_queries_examples.sql
-- Complex MySQL queries demonstrating advanced SQL features
-- =========================================================

USE UniLibPlus;

-- =========================================================
-- PART 1: BASIC QUERIES (Simple examples)
-- =========================================================

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

-- =========================================================
-- PART 2: COMPLEX QUERIES (Advanced SQL features)
-- =========================================================

-- ---------------------------------------------------------
-- Q11. Correlated Subquery: Find books that have more copies
--      than the average number of copies per book
-- ---------------------------------------------------------
SELECT
  b.isbn,
  b.title,
  COUNT(c.copy_id) AS copy_count
FROM Book b
JOIN Copy c ON b.isbn = c.isbn
GROUP BY b.isbn, b.title
HAVING copy_count > (
  SELECT AVG(copy_count)
  FROM (
    SELECT COUNT(copy_id) AS copy_count
    FROM Copy
    GROUP BY isbn
  ) AS avg_copies
)
ORDER BY copy_count DESC;

-- ---------------------------------------------------------
-- Q12. Window Functions: Rank patrons by total fines within each patron type
--      Using ROW_NUMBER, RANK, and DENSE_RANK
-- ---------------------------------------------------------
SELECT
  patron_id,
  first_name,
  last_name,
  patron_type,
  total_fines,
  unpaid_fines,
  ROW_NUMBER() OVER (PARTITION BY patron_type ORDER BY total_fines DESC) AS row_num,
  RANK() OVER (PARTITION BY patron_type ORDER BY total_fines DESC) AS rank_fines,
  DENSE_RANK() OVER (PARTITION BY patron_type ORDER BY total_fines DESC) AS dense_rank_fines
FROM vw_patron_fines_summary
JOIN Patron p USING (patron_id)
WHERE total_fines > 0
ORDER BY patron_type, total_fines DESC;

-- ---------------------------------------------------------
-- Q13. Window Functions with LAG/LEAD: Compare each loan's duration
--      with the previous loan for the same patron
-- ---------------------------------------------------------
SELECT
  loan_id,
  patron_id,
  isbn,
  title,
  loan_ts,
  return_ts,
  DATEDIFF(COALESCE(return_ts, NOW()), loan_ts) AS loan_duration_days,
  LAG(DATEDIFF(COALESCE(return_ts, NOW()), loan_ts)) 
    OVER (PARTITION BY patron_id ORDER BY loan_ts) AS prev_loan_duration,
  DATEDIFF(COALESCE(return_ts, NOW()), loan_ts) - 
    LAG(DATEDIFF(COALESCE(return_ts, NOW()), loan_ts)) 
      OVER (PARTITION BY patron_id ORDER BY loan_ts) AS duration_diff
FROM vw_patron_loans_with_status
WHERE return_ts IS NOT NULL
ORDER BY patron_id, loan_ts;

-- ---------------------------------------------------------
-- Q14. Common Table Expression (CTE): Find patrons with loans
--      in multiple branches using recursive-like logic
-- ---------------------------------------------------------
WITH PatronBranchLoans AS (
  SELECT DISTINCT
    l.patron_id,
    c.branch_id,
  br.name AS branch_name,
    COUNT(DISTINCT l.loan_id) AS loans_at_branch
  FROM Loan l
  JOIN Copy c ON l.copy_id = c.copy_id
  JOIN Branch br ON c.branch_id = br.branch_id
  GROUP BY l.patron_id, c.branch_id, br.name
),
MultiBranchPatrons AS (
  SELECT
    patron_id,
    COUNT(DISTINCT branch_id) AS num_branches,
    SUM(loans_at_branch) AS total_loans
  FROM PatronBranchLoans
  GROUP BY patron_id
  HAVING num_branches > 1
)
SELECT
  p.patron_id,
  CONCAT(p.first_name, ' ', p.last_name) AS patron_name,
  mbp.num_branches,
  mbp.total_loans,
  GROUP_CONCAT(DISTINCT pbl.branch_name ORDER BY pbl.branch_name SEPARATOR ', ') AS branches_used
FROM MultiBranchPatrons mbp
JOIN Patron p ON mbp.patron_id = p.patron_id
JOIN PatronBranchLoans pbl ON mbp.patron_id = pbl.patron_id
GROUP BY p.patron_id, patron_name, mbp.num_branches, mbp.total_loans
ORDER BY mbp.num_branches DESC, mbp.total_loans DESC;

-- ---------------------------------------------------------
-- Q15. Complex CASE with Aggregation: Categorize books by popularity
--      and calculate statistics for each category
-- ---------------------------------------------------------
SELECT
  CASE
    WHEN loan_count = 0 THEN 'Never Loaned'
    WHEN loan_count BETWEEN 1 AND 5 THEN 'Low Popularity (1-5 loans)'
    WHEN loan_count BETWEEN 6 AND 15 THEN 'Medium Popularity (6-15 loans)'
    WHEN loan_count BETWEEN 16 AND 30 THEN 'High Popularity (16-30 loans)'
    ELSE 'Very High Popularity (30+ loans)'
  END AS popularity_category,
  COUNT(*) AS num_books,
  AVG(loan_count) AS avg_loans_per_book,
  MIN(loan_count) AS min_loans,
  MAX(loan_count) AS max_loans,
  SUM(loan_count) AS total_loans
FROM (
  SELECT
    b.isbn,
    b.title,
    COUNT(l.loan_id) AS loan_count
  FROM Book b
  LEFT JOIN Copy c ON b.isbn = c.isbn
  LEFT JOIN Loan l ON c.copy_id = l.copy_id
  GROUP BY b.isbn, b.title
) AS book_loans
GROUP BY popularity_category
ORDER BY 
  CASE popularity_category
    WHEN 'Never Loaned' THEN 1
    WHEN 'Low Popularity (1-5 loans)' THEN 2
    WHEN 'Medium Popularity (6-15 loans)' THEN 3
    WHEN 'High Popularity (16-30 loans)' THEN 4
    ELSE 5
  END;

-- ---------------------------------------------------------
-- Q16. EXISTS Subquery: Find patrons who have never borrowed
--      any books but have active reservations
-- ---------------------------------------------------------
SELECT
  p.patron_id,
  CONCAT(p.first_name, ' ', p.last_name) AS patron_name,
  p.email,
  p.patron_type,
  COUNT(r.reservation_id) AS active_reservations
FROM Patron p
JOIN Reservation r ON p.patron_id = r.patron_id
WHERE r.status IN ('Active', 'Waiting')
  AND NOT EXISTS (
    SELECT 1
    FROM Loan l
    WHERE l.patron_id = p.patron_id
  )
GROUP BY p.patron_id, patron_name, p.email, p.patron_type
ORDER BY active_reservations DESC, patron_name;

-- ---------------------------------------------------------
-- Q17. NOT EXISTS with Multiple Conditions: Find books that
--      have copies but have never been loaned
-- ---------------------------------------------------------
SELECT
  b.isbn,
  b.title,
  COUNT(DISTINCT c.copy_id) AS num_copies,
  COUNT(DISTINCT c.branch_id) AS num_branches
FROM Book b
JOIN Copy c ON b.isbn = c.isbn
WHERE NOT EXISTS (
  SELECT 1
  FROM Loan l
  WHERE l.copy_id = c.copy_id
)
GROUP BY b.isbn, b.title
ORDER BY num_copies DESC, b.title;

-- ---------------------------------------------------------
-- Q18. UNION: Combine overdue loans and books with no copies
--      available as "action items"
-- ---------------------------------------------------------
SELECT
  'Overdue Loan' AS item_type,
  CAST(loan_id AS CHAR) AS item_id,
  CONCAT('Patron: ', patron_name, ' - Book: ', title) AS description,
  due_ts AS action_date,
  DATEDIFF(NOW(), due_ts) AS days_overdue
FROM vw_overdue_loans

UNION ALL

SELECT
  'No Copies Available' AS item_type,
  b.isbn AS item_id,
  CONCAT('Book: ', b.title, ' has reservations but no available copies') AS description,
  MAX(r.created_at) AS action_date,
  DATEDIFF(NOW(), MAX(r.created_at)) AS days_waiting
FROM Book b
JOIN Reservation r ON b.isbn = r.isbn
WHERE r.status IN ('Active', 'Waiting')
  AND NOT EXISTS (
    SELECT 1
    FROM Copy c
    LEFT JOIN Loan l ON c.copy_id = l.copy_id
    WHERE c.isbn = b.isbn
      AND (l.return_ts IS NULL OR l.loan_id IS NULL)
  )
GROUP BY b.isbn, b.title

ORDER BY action_date;

-- ---------------------------------------------------------
-- Q19. Self-Join: Find patrons who have borrowed the same book
--      multiple times (repeat borrowers)
-- ---------------------------------------------------------
SELECT
  p.patron_id,
  CONCAT(p.first_name, ' ', p.last_name) AS patron_name,
  b.isbn,
  b.title,
  COUNT(DISTINCT l1.loan_id) AS times_borrowed,
  MIN(l1.loan_ts) AS first_loan,
  MAX(l1.loan_ts) AS last_loan,
  DATEDIFF(MAX(l1.loan_ts), MIN(l1.loan_ts)) AS days_between_first_last
FROM Patron p
JOIN Loan l1 ON p.patron_id = l1.patron_id
JOIN Copy c1 ON l1.copy_id = c1.copy_id
JOIN Book b ON c1.isbn = b.isbn
GROUP BY p.patron_id, patron_name, b.isbn, b.title
HAVING times_borrowed > 1
ORDER BY times_borrowed DESC, patron_name, b.title;

-- ---------------------------------------------------------
-- Q20. Complex Aggregation with HAVING: Find branches where
--      the average loan duration exceeds the overall average
-- ---------------------------------------------------------
SELECT
  br.branch_id,
  br.name AS branch_name,
  COUNT(DISTINCT l.loan_id) AS total_loans,
  COUNT(DISTINCT l.patron_id) AS unique_patrons,
  AVG(DATEDIFF(COALESCE(l.return_ts, NOW()), l.loan_ts)) AS avg_loan_duration_days,
  (
    SELECT AVG(DATEDIFF(COALESCE(return_ts, NOW()), loan_ts))
    FROM Loan
  ) AS overall_avg_duration
FROM Branch br
JOIN Copy c ON br.branch_id = c.branch_id
JOIN Loan l ON c.copy_id = l.copy_id
GROUP BY br.branch_id, br.name
HAVING avg_loan_duration_days > overall_avg_duration
ORDER BY avg_loan_duration_days DESC;

-- ---------------------------------------------------------
-- Q21. Window Functions with PARTITION BY: Calculate running
--      totals and percentages for book loans by month
-- ---------------------------------------------------------
SELECT
  DATE_FORMAT(loan_ts, '%Y-%m') AS loan_month,
  COUNT(*) AS loans_in_month,
  SUM(COUNT(*)) OVER (ORDER BY DATE_FORMAT(loan_ts, '%Y-%m')) AS running_total_loans,
  ROUND(
    100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
    2
  ) AS percentage_of_total,
  ROUND(
    100.0 * COUNT(*) / LAG(COUNT(*)) OVER (ORDER BY DATE_FORMAT(loan_ts, '%Y-%m')),
    2
  ) AS pct_change_from_prev_month
FROM Loan
WHERE loan_ts IS NOT NULL
GROUP BY loan_month
ORDER BY loan_month;

-- ---------------------------------------------------------
-- Q22. Multiple CTEs with Complex Joins: Analyze patron
--      borrowing patterns by subject area
-- ---------------------------------------------------------
WITH PatronSubjectLoans AS (
  SELECT
    l.patron_id,
    s.subject_id,
    s.name AS subject_name,
    COUNT(DISTINCT l.loan_id) AS loan_count,
    COUNT(DISTINCT b.isbn) AS unique_books
  FROM Loan l
  JOIN Copy c ON l.copy_id = c.copy_id
  JOIN Book b ON c.isbn = b.isbn
  JOIN BookSubject bs ON b.isbn = bs.isbn
  JOIN Subject s ON bs.subject_id = s.subject_id
  GROUP BY l.patron_id, s.subject_id, s.name
),
PatronTotalLoans AS (
  SELECT
    patron_id,
    SUM(loan_count) AS total_loans
  FROM PatronSubjectLoans
  GROUP BY patron_id
)
SELECT
  p.patron_id,
  CONCAT(p.first_name, ' ', p.last_name) AS patron_name,
  p.patron_type,
  psl.subject_name,
  psl.loan_count,
  psl.unique_books,
  ROUND(100.0 * psl.loan_count / ptl.total_loans, 2) AS pct_of_total_loans
FROM PatronSubjectLoans psl
JOIN Patron p ON psl.patron_id = p.patron_id
JOIN PatronTotalLoans ptl ON p.patron_id = ptl.patron_id
WHERE ptl.total_loans >= 5  -- Only patrons with 5+ loans
ORDER BY p.patron_id, psl.loan_count DESC;

-- ---------------------------------------------------------
-- Q23. Conditional Aggregation with CASE: Analyze fine reasons
--      and calculate statistics by reason type
-- ---------------------------------------------------------
SELECT
  fr.code AS fine_reason_code,
  fr.description AS fine_reason,
  COUNT(f.fine_id) AS total_fines,
  SUM(f.amount) AS total_amount,
  AVG(f.amount) AS avg_amount,
  MIN(f.amount) AS min_amount,
  MAX(f.amount) AS max_amount,
  SUM(CASE WHEN f.status = 'Paid' THEN f.amount ELSE 0 END) AS paid_amount,
  SUM(CASE WHEN f.status = 'Unpaid' THEN f.amount ELSE 0 END) AS unpaid_amount,
  COUNT(CASE WHEN f.status = 'Paid' THEN 1 END) AS paid_count,
  COUNT(CASE WHEN f.status = 'Unpaid' THEN 1 END) AS unpaid_count,
  ROUND(
    100.0 * COUNT(CASE WHEN f.status = 'Paid' THEN 1 END) / COUNT(f.fine_id),
    2
  ) AS payment_rate_pct
FROM FineReason fr
LEFT JOIN Fine f ON fr.reason_id = f.reason_id
GROUP BY fr.reason_id, fr.code, fr.description
ORDER BY total_amount DESC;

-- ---------------------------------------------------------
-- Q24. Recursive-like Query with Date Functions: Find patrons
--      with consecutive months of borrowing activity
-- ---------------------------------------------------------
WITH MonthlyLoans AS (
  SELECT
    patron_id,
    DATE_FORMAT(loan_ts, '%Y-%m') AS loan_month,
    COUNT(*) AS loans_in_month
  FROM Loan
  GROUP BY patron_id, loan_month
),
ConsecutiveMonths AS (
  SELECT
    ml1.patron_id,
    ml1.loan_month AS start_month,
    COUNT(*) AS consecutive_months
  FROM MonthlyLoans ml1
  WHERE NOT EXISTS (
    SELECT 1
    FROM MonthlyLoans ml2
    WHERE ml2.patron_id = ml1.patron_id
      AND ml2.loan_month = DATE_FORMAT(
        DATE_SUB(STR_TO_DATE(CONCAT(ml1.loan_month, '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH),
        '%Y-%m'
      )
  )
  GROUP BY ml1.patron_id, ml1.loan_month
)
SELECT
  p.patron_id,
  CONCAT(p.first_name, ' ', p.last_name) AS patron_name,
  cm.start_month,
  cm.consecutive_months,
  SUM(ml.loans_in_month) AS total_loans_in_period
FROM ConsecutiveMonths cm
JOIN Patron p ON cm.patron_id = p.patron_id
JOIN MonthlyLoans ml ON cm.patron_id = ml.patron_id
  AND ml.loan_month >= cm.start_month
GROUP BY p.patron_id, patron_name, cm.start_month, cm.consecutive_months
HAVING consecutive_months >= 3
ORDER BY consecutive_months DESC, total_loans_in_period DESC;

-- ---------------------------------------------------------
-- Q25. PIVOT-like Operation using CASE: Show loan counts
--      by patron type and month (cross-tabulation)
-- ---------------------------------------------------------
SELECT
  DATE_FORMAT(loan_ts, '%Y-%m') AS loan_month,
  SUM(CASE WHEN p.patron_type = 'Student' THEN 1 ELSE 0 END) AS student_loans,
  SUM(CASE WHEN p.patron_type = 'Faculty' THEN 1 ELSE 0 END) AS faculty_loans,
  SUM(CASE WHEN p.patron_type = 'Staff' THEN 1 ELSE 0 END) AS staff_loans,
  SUM(CASE WHEN p.patron_type = 'Alumni' THEN 1 ELSE 0 END) AS alumni_loans,
  COUNT(*) AS total_loans
FROM Loan l
JOIN Patron p ON l.patron_id = p.patron_id
WHERE loan_ts IS NOT NULL
GROUP BY loan_month
ORDER BY loan_month DESC;

-- ---------------------------------------------------------
-- Q26. Complex Subquery with ALL: Find books that are more
--      popular than ALL books published before a certain year
-- ---------------------------------------------------------
SELECT
  b.isbn,
  b.title,
  b.pub_year,
  COUNT(l.loan_id) AS loan_count
FROM Book b
LEFT JOIN Copy c ON b.isbn = c.isbn
LEFT JOIN Loan l ON c.copy_id = l.copy_id
WHERE b.pub_year >= 2010
GROUP BY b.isbn, b.title, b.pub_year
HAVING loan_count > ALL (
  SELECT COUNT(l2.loan_id)
  FROM Book b2
  LEFT JOIN Copy c2 ON b2.isbn = c2.isbn
  LEFT JOIN Loan l2 ON c2.copy_id = l2.copy_id
  WHERE b2.pub_year < 2010
  GROUP BY b2.isbn
)
ORDER BY loan_count DESC;

-- ---------------------------------------------------------
-- Q27. INTERSECT-like using EXISTS: Find books borrowed by
--      both students and faculty
-- ---------------------------------------------------------
SELECT DISTINCT
  b.isbn,
  b.title
FROM Book b
WHERE EXISTS (
  SELECT 1
  FROM Loan l1
  JOIN Copy c1 ON l1.copy_id = c1.copy_id
  JOIN Patron p1 ON l1.patron_id = p1.patron_id
  WHERE c1.isbn = b.isbn
    AND p1.patron_type = 'Student'
)
AND EXISTS (
  SELECT 1
  FROM Loan l2
  JOIN Copy c2 ON l2.copy_id = c2.copy_id
  JOIN Patron p2 ON l2.patron_id = p2.patron_id
  WHERE c2.isbn = b.isbn
    AND p2.patron_type = 'Faculty'
)
ORDER BY b.title;

-- ---------------------------------------------------------
-- Q28. Window Function with FIRST_VALUE/LAST_VALUE: For each
--      book, show the first and last loan dates
-- ---------------------------------------------------------
SELECT
  isbn,
  title,
  total_loans,
  first_loan_date,
  last_loan_date,
  DATEDIFF(last_loan_date, first_loan_date) AS days_between_first_last
FROM (
  SELECT
    b.isbn,
    b.title,
    COUNT(l.loan_id) OVER (PARTITION BY b.isbn) AS total_loans,
    FIRST_VALUE(l.loan_ts) OVER (
      PARTITION BY b.isbn 
      ORDER BY l.loan_ts 
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_loan_date,
    LAST_VALUE(l.loan_ts) OVER (
      PARTITION BY b.isbn 
      ORDER BY l.loan_ts 
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_loan_date
  FROM Book b
  JOIN Copy c ON b.isbn = c.isbn
  JOIN Loan l ON c.copy_id = l.copy_id
) AS book_loan_stats
GROUP BY isbn, title, total_loans, first_loan_date, last_loan_date
HAVING total_loans > 1
ORDER BY total_loans DESC
LIMIT 20;

-- ---------------------------------------------------------
-- Q29. Multiple Aggregations with GROUPING SETS equivalent:
--      Summary statistics at different levels
-- ---------------------------------------------------------
SELECT
  COALESCE(p.patron_type, 'ALL TYPES') AS patron_type,
  COALESCE(DATE_FORMAT(l.loan_ts, '%Y'), 'ALL YEARS') AS loan_year,
  COUNT(DISTINCT l.patron_id) AS unique_patrons,
  COUNT(l.loan_id) AS total_loans,
  AVG(DATEDIFF(COALESCE(l.return_ts, NOW()), l.loan_ts)) AS avg_duration_days
FROM Loan l
JOIN Patron p ON l.patron_id = p.patron_id
GROUP BY p.patron_type, DATE_FORMAT(l.loan_ts, '%Y')
WITH ROLLUP
ORDER BY patron_type, loan_year;

-- ---------------------------------------------------------
-- Q30. Complex Query with String Functions and Pattern Matching:
--      Analyze author names and find co-author relationships
-- ---------------------------------------------------------
SELECT
  a1.author_id AS author1_id,
  CONCAT(a1.first_name, ' ', a1.last_name) AS author1_name,
  a2.author_id AS author2_id,
  CONCAT(a2.first_name, ' ', a2.last_name) AS author2_name,
  COUNT(DISTINCT b.isbn) AS books_together
FROM Author a1
JOIN BookAuthor ba1 ON a1.author_id = ba1.author_id
JOIN BookAuthor ba2 ON ba1.isbn = ba2.isbn
JOIN Author a2 ON ba2.author_id = a2.author_id
JOIN Book b ON ba1.isbn = b.isbn
WHERE a1.author_id < a2.author_id  -- Avoid duplicates and self-joins
GROUP BY a1.author_id, author1_name, a2.author_id, author2_name
HAVING books_together >= 2
ORDER BY books_together DESC, author1_name, author2_name;

-- =========================================================
-- End of 07_queries_examples.sql
-- =========================================================
