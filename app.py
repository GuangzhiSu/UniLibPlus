from flask import Flask, render_template, request, redirect, url_for
import pymysql
from datetime import datetime

app = Flask(__name__)

# Jinja2 filter for date formatting
@app.template_filter('dateformat')
def dateformat(value, format='%Y-%m-%d'):
    """Format a date value"""
    if value is None:
        return 'N/A'
    if isinstance(value, str):
        try:
            value = datetime.strptime(value, '%Y-%m-%d %H:%M:%S')
        except:
            try:
                value = datetime.strptime(value, '%Y-%m-%d')
            except:
                return value
    if isinstance(value, datetime):
        return value.strftime(format)
    return str(value)

# -----------------------------
# Database connection helper
# -----------------------------
def get_connection():
    return pymysql.connect(
        host="localhost",
        port=3307,
        user="root",
        password="Qh#330320",
        database="UniLibPlus",
        cursorclass=pymysql.cursors.DictCursor,
        charset="utf8mb4"
    )

# -----------------------------
# Dashboard - Home page with statistics
# -----------------------------
@app.route("/")
@app.route("/dashboard")
def dashboard():
    conn = get_connection()
    stats = {}
    try:
        with conn.cursor() as cur:
            # Total books
            cur.execute("SELECT COUNT(*) as count FROM Book")
            stats['total_books'] = cur.fetchone()['count']
            
            # Total patrons
            cur.execute("SELECT COUNT(*) as count FROM Patron")
            stats['total_patrons'] = cur.fetchone()['count']
            
            # Current loans
            cur.execute("SELECT COUNT(*) as count FROM vw_current_loans")
            stats['current_loans'] = cur.fetchone()['count']
            
            # Overdue loans
            cur.execute("SELECT COUNT(*) as count FROM vw_overdue_loans")
            stats['overdue_loans'] = cur.fetchone()['count']
            
            # Total fines
            cur.execute("""
                SELECT COALESCE(SUM(unpaid_fines), 0) as total 
                FROM vw_patron_fines_summary
            """)
            stats['total_fines'] = cur.fetchone()['total'] or 0
            
            # Recent overdue loans
            cur.execute("""
                SELECT loan_id, patron_name, title, due_ts
                FROM vw_overdue_loans
                ORDER BY due_ts
                LIMIT 5
            """)
            stats['recent_overdue'] = cur.fetchall()
            
    finally:
        conn.close()
    
    return render_template("dashboard.html", stats=stats)

# -----------------------------
# Books - Enhanced with search and filters
# -----------------------------
@app.route("/books")
def books():
    search = request.args.get('search', '')
    subject = request.args.get('subject', '')
    
    conn = get_connection()
    books = []
    subjects = []
    
    try:
        with conn.cursor() as cur:
            # Get all subjects for filter
            cur.execute("SELECT DISTINCT subject_id, name FROM Subject ORDER BY name")
            subjects = cur.fetchall()
            
            # Get books with details
            if subject:
                sql = """
                    SELECT DISTINCT
                        b.isbn,
                        b.title,
                        b.pub_year,
                        p.name AS publisher_name,
                        GROUP_CONCAT(DISTINCT CONCAT(a.first_name, ' ', a.last_name) SEPARATOR ', ') AS authors,
                        GROUP_CONCAT(DISTINCT s.name SEPARATOR ', ') AS subjects
                    FROM Book b
                    LEFT JOIN Publisher p ON b.publisher_id = p.publisher_id
                    LEFT JOIN BookAuthor ba ON b.isbn = ba.isbn
                    LEFT JOIN Author a ON ba.author_id = a.author_id
                    LEFT JOIN BookSubject bs ON b.isbn = bs.isbn
                    LEFT JOIN Subject s ON bs.subject_id = s.subject_id
                    WHERE 1=1
                """
                params = []
                
                if search:
                    sql += " AND (b.title LIKE %s OR b.isbn LIKE %s)"
                    params.extend([f'%{search}%', f'%{search}%'])
                
                if subject:
                    sql += " AND s.subject_id = %s"
                    params.append(subject)
                
                sql += """
                    GROUP BY b.isbn, b.title, b.pub_year, p.name
                    ORDER BY b.title
                """
                cur.execute(sql, params)
            else:
                sql = """
                    SELECT DISTINCT
                        b.isbn,
                        b.title,
                        b.pub_year,
                        p.name AS publisher_name,
                        GROUP_CONCAT(DISTINCT CONCAT(a.first_name, ' ', a.last_name) SEPARATOR ', ') AS authors,
                        GROUP_CONCAT(DISTINCT s.name SEPARATOR ', ') AS subjects
                    FROM Book b
                    LEFT JOIN Publisher p ON b.publisher_id = p.publisher_id
                    LEFT JOIN BookAuthor ba ON b.isbn = ba.isbn
                    LEFT JOIN Author a ON ba.author_id = a.author_id
                    LEFT JOIN BookSubject bs ON b.isbn = bs.isbn
                    LEFT JOIN Subject s ON bs.subject_id = s.subject_id
                    WHERE 1=1
                """
                params = []
                
                if search:
                    sql += " AND (b.title LIKE %s OR b.isbn LIKE %s)"
                    params.extend([f'%{search}%', f'%{search}%'])
                
                sql += """
                    GROUP BY b.isbn, b.title, b.pub_year, p.name
                    ORDER BY b.title
                """
                cur.execute(sql, params)
            
            books = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("books.html", books=books, subjects=subjects, search=search, selected_subject=subject)

# -----------------------------
# Book Details
# -----------------------------
@app.route("/book/<isbn>")
def book_detail(isbn):
    conn = get_connection()
    book = None
    copies = []
    
    try:
        with conn.cursor() as cur:
            # Get book details
            cur.execute("""
                SELECT 
                    b.isbn,
                    b.title,
                    b.pub_year,
                    p.name AS publisher_name,
                    GROUP_CONCAT(DISTINCT CONCAT(a.first_name, ' ', a.last_name) SEPARATOR ', ') AS authors,
                    GROUP_CONCAT(DISTINCT s.name SEPARATOR ', ') AS subjects
                FROM Book b
                LEFT JOIN Publisher p ON b.publisher_id = p.publisher_id
                LEFT JOIN BookAuthor ba ON b.isbn = ba.isbn
                LEFT JOIN Author a ON ba.author_id = a.author_id
                LEFT JOIN BookSubject bs ON b.isbn = bs.isbn
                LEFT JOIN Subject s ON bs.subject_id = s.subject_id
                WHERE b.isbn = %s
                GROUP BY b.isbn, b.title, b.pub_year, p.name
            """, (isbn,))
            book = cur.fetchone()
            
            # Get copy locations
            cur.execute("""
                SELECT copy_id, barcode, branch_name, checkin_term
                FROM vw_copy_location
                WHERE isbn = %s
            """, (isbn,))
            copies = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("book_detail.html", book=book, copies=copies)

# -----------------------------
# Patrons - Enhanced
# -----------------------------
@app.route("/patrons", methods=["GET", "POST"])
def patrons():
    if request.method == "POST":
        first_name = request.form.get("first_name")
        last_name = request.form.get("last_name")
        email = request.form.get("email")
        patron_type = request.form.get("patron_type")
        address_id = request.form.get("address_id")

        if first_name and last_name and patron_type:
            conn = get_connection()
            try:
                with conn.cursor() as cur:
                    sql = """
                        INSERT INTO Patron (patron_id, first_name, last_name, email, patron_type, address_id, balance)
                        VALUES (
                            (SELECT COALESCE(MAX(patron_id), 0) + 1 FROM Patron p2),
                            %s, %s, %s, %s, %s, 0.00
                        )
                    """
                    cur.execute(sql, (first_name, last_name, email, patron_type, address_id or None))
                conn.commit()
            finally:
                conn.close()

        return redirect(url_for("patrons"))

    # GET: show list of patrons with fines
    conn = get_connection()
    patrons = []
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT 
                    p.patron_id,
                    p.first_name,
                    p.last_name,
                    p.email,
                    p.patron_type,
                    p.balance,
                    COALESCE(ps.total_fines, 0) as total_fines,
                    COALESCE(ps.unpaid_fines, 0) as unpaid_fines
                FROM Patron p
                LEFT JOIN vw_patron_fines_summary ps ON p.patron_id = ps.patron_id
                ORDER BY p.patron_id
            """)
            patrons = cur.fetchall()
    finally:
        conn.close()

    return render_template("patrons.html", patrons=patrons)

# -----------------------------
# Patron Details
# -----------------------------
@app.route("/patron/<int:patron_id>")
def patron_detail(patron_id):
    conn = get_connection()
    patron = None
    loans = []
    fines = None
    
    try:
        with conn.cursor() as cur:
            # Get patron info
            cur.execute("""
                SELECT p.*, ps.total_fines, ps.unpaid_fines
                FROM Patron p
                LEFT JOIN vw_patron_fines_summary ps ON p.patron_id = ps.patron_id
                WHERE p.patron_id = %s
            """, (patron_id,))
            patron = cur.fetchone()
            
            # Get loan history
            cur.execute("""
                SELECT loan_id, copy_id, barcode, isbn, title, loan_ts, due_ts, return_ts, loan_status
                FROM vw_patron_loans_with_status
                WHERE patron_id = %s
                ORDER BY loan_ts DESC
            """, (patron_id,))
            loans = cur.fetchall()
            
            # Get fines summary
            cur.execute("""
                SELECT total_fines, unpaid_fines
                FROM vw_patron_fines_summary
                WHERE patron_id = %s
            """, (patron_id,))
            fines = cur.fetchone()
    finally:
        conn.close()
    
    return render_template("patron_detail.html", patron=patron, loans=loans, fines=fines)

# -----------------------------
# Loans Management
# -----------------------------
@app.route("/loans")
def loans():
    filter_type = request.args.get('filter', 'all')  # all, current, overdue, returned
    
    conn = get_connection()
    loans = []
    
    try:
        with conn.cursor() as cur:
            if filter_type == 'current':
                cur.execute("""
                    SELECT loan_id, copy_id, barcode, isbn, title, patron_id, patron_name, loan_ts, due_ts
                    FROM vw_current_loans
                    ORDER BY due_ts
                """)
            elif filter_type == 'overdue':
                cur.execute("""
                    SELECT loan_id, copy_id, barcode, isbn, title, patron_id, patron_name, loan_ts, due_ts
                    FROM vw_overdue_loans
                    ORDER BY due_ts
                """)
            else:
                cur.execute("""
                    SELECT loan_id, patron_id, patron_name, copy_id, barcode, isbn, title, loan_ts, due_ts, return_ts, loan_status
                    FROM vw_patron_loans_with_status
                    ORDER BY loan_ts DESC
                    LIMIT 100
                """)
            
            loans = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("loans.html", loans=loans, filter_type=filter_type)

# -----------------------------
# Fines Management
# -----------------------------
@app.route("/fines")
def fines():
    conn = get_connection()
    fines_list = []
    
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT patron_id, first_name, last_name, email, total_fines, unpaid_fines
                FROM vw_patron_fines_summary
                WHERE unpaid_fines > 0
                ORDER BY unpaid_fines DESC
            """)
            fines_list = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("fines.html", fines_list=fines_list)

# -----------------------------
# Statistics
# -----------------------------
@app.route("/statistics")
def statistics():
    conn = get_connection()
    top_books = []
    top_patrons = []
    
    try:
        with conn.cursor() as cur:
            # Top 10 most popular books
            cur.execute("""
                SELECT b.isbn, b.title, COUNT(l.loan_id) AS times_loaned
                FROM Book b
                JOIN Copy c ON b.isbn = c.isbn
                JOIN Loan l ON c.copy_id = l.copy_id
                GROUP BY b.isbn, b.title
                ORDER BY times_loaned DESC, b.title
                LIMIT 10
            """)
            top_books = cur.fetchall()
            
            # Top 10 patrons by loans
            cur.execute("""
                SELECT p.patron_id,
                       CONCAT(p.first_name, ' ', p.last_name) AS patron_name,
                       COUNT(l.loan_id) AS loan_count
                FROM Patron p
                LEFT JOIN Loan l ON p.patron_id = l.patron_id
                GROUP BY p.patron_id, patron_name
                ORDER BY loan_count DESC
                LIMIT 10
            """)
            top_patrons = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("statistics.html", top_books=top_books, top_patrons=top_patrons)

# -----------------------------
# Analytics - Complex Queries
# -----------------------------
@app.route("/analytics")
def analytics():
    """Main analytics page with links to complex queries"""
    return render_template("analytics.html")

# -----------------------------
# Q12: Window Functions - Rank patrons by fines within each type
# -----------------------------
@app.route("/analytics/patron-ranking")
def patron_ranking():
    conn = get_connection()
    rankings = []
    
    try:
        with conn.cursor() as cur:
            cur.execute("""
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
                ORDER BY patron_type, total_fines DESC
            """)
            rankings = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("analytics_patron_ranking.html", rankings=rankings)

# -----------------------------
# Q14: CTE - Patrons with loans in multiple branches
# -----------------------------
@app.route("/analytics/multi-branch-patrons")
def multi_branch_patrons():
    conn = get_connection()
    patrons = []
    
    try:
        with conn.cursor() as cur:
            cur.execute("""
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
                ORDER BY mbp.num_branches DESC, mbp.total_loans DESC
            """)
            patrons = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("analytics_multi_branch.html", patrons=patrons)

# -----------------------------
# Q15: Complex CASE - Book popularity categories
# -----------------------------
@app.route("/analytics/book-popularity")
def book_popularity():
    conn = get_connection()
    categories = []
    
    try:
        with conn.cursor() as cur:
            cur.execute("""
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
                  END
            """)
            categories = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("analytics_book_popularity.html", categories=categories)

# -----------------------------
# Q16: EXISTS - Patrons with reservations but no loans
# -----------------------------
@app.route("/analytics/reservations-no-loans")
def reservations_no_loans():
    conn = get_connection()
    patrons = []
    
    try:
        with conn.cursor() as cur:
            cur.execute("""
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
                ORDER BY active_reservations DESC, patron_name
            """)
            patrons = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("analytics_reservations_no_loans.html", patrons=patrons)

# -----------------------------
# Q19: Self-Join - Repeat borrowers of same book
# -----------------------------
@app.route("/analytics/repeat-borrowers")
def repeat_borrowers():
    conn = get_connection()
    borrowers = []
    
    try:
        with conn.cursor() as cur:
            cur.execute("""
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
                ORDER BY times_borrowed DESC, patron_name, b.title
            """)
            borrowers = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("analytics_repeat_borrowers.html", borrowers=borrowers)

# -----------------------------
# Q23: Fine analysis by reason
# -----------------------------
@app.route("/analytics/fine-analysis")
def fine_analysis():
    conn = get_connection()
    fine_stats = []
    
    try:
        with conn.cursor() as cur:
            cur.execute("""
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
                ORDER BY total_amount DESC
            """)
            fine_stats = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("analytics_fine_analysis.html", fine_stats=fine_stats)

# -----------------------------
# Q22: Patron borrowing patterns by subject
# -----------------------------
@app.route("/analytics/subject-patterns")
def subject_patterns():
    patron_id = request.args.get('patron_id', '')
    conn = get_connection()
    patterns = []
    
    try:
        with conn.cursor() as cur:
            if patron_id:
                sql = """
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
                      WHERE l.patron_id = %s
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
                    WHERE ptl.total_loans >= 5
                    ORDER BY psl.loan_count DESC
                """
                cur.execute(sql, (patron_id,))
            else:
                sql = """
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
                    WHERE ptl.total_loans >= 5
                    ORDER BY p.patron_id, psl.loan_count DESC
                    LIMIT 100
                """
                cur.execute(sql)
            
            patterns = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("analytics_subject_patterns.html", patterns=patterns, patron_id=patron_id)

# -----------------------------
# Q25: Monthly loans by patron type (PIVOT-like)
# -----------------------------
@app.route("/analytics/monthly-loans")
def monthly_loans():
    conn = get_connection()
    monthly_data = []
    
    try:
        with conn.cursor() as cur:
            cur.execute("""
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
                ORDER BY loan_month DESC
            """)
            monthly_data = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("analytics_monthly_loans.html", monthly_data=monthly_data)

# -----------------------------
# Q30: Co-author relationships
# -----------------------------
@app.route("/analytics/co-authors")
def co_authors():
    conn = get_connection()
    coauthors = []
    
    try:
        with conn.cursor() as cur:
            cur.execute("""
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
                WHERE a1.author_id < a2.author_id
                GROUP BY a1.author_id, author1_name, a2.author_id, author2_name
                HAVING books_together >= 2
                ORDER BY books_together DESC, author1_name, author2_name
            """)
            coauthors = cur.fetchall()
    finally:
        conn.close()
    
    return render_template("analytics_co_authors.html", coauthors=coauthors)

if __name__ == "__main__":
    app.run(debug=True)
