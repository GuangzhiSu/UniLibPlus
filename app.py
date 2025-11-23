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

if __name__ == "__main__":
    app.run(debug=True)
