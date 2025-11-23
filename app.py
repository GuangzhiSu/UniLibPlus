from flask import Flask, render_template, request, redirect, url_for
import pymysql

app = Flask(__name__)

# -----------------------------
# Database connection helper
# -----------------------------
def get_connection():
    return pymysql.connect(
        host="localhost",        # MySQL host
        port = 3306,
        user="root",             # your MySQL username
        password="Qh#330320",# your MySQL password
        database="UniLibPlus",   # your database name
        cursorclass=pymysql.cursors.DictCursor,
        charset="utf8mb4"
    )

# -----------------------------
# Route: home page
# Show patrons + add new patron
# -----------------------------
@app.route("/", methods=["GET", "POST"])
def index():
    if request.method == "POST":
        # Handle form submission to insert a new patron
        first_name = request.form.get("first_name")
        last_name = request.form.get("last_name")
        email = request.form.get("email")
        patron_type = request.form.get("patron_type")
        address_id = request.form.get("address_id")

        # Simple validation: you can add more checks
        if first_name and last_name and patron_type:
            conn = get_connection()
            try:
                with conn.cursor() as cur:
                    sql = """
                        INSERT INTO Patron (patron_id, first_name, last_name, email, patron_type, address_id, balance)
                        VALUES (
                            (SELECT COALESCE(MAX(patron_id), 0) + 1 FROM Patron p2),
                            %s, %s, %s, %s, %s, 0.00
                        );
                    """
                    cur.execute(sql, (first_name, last_name, email, patron_type, address_id or None))
                conn.commit()
            finally:
                conn.close()

        return redirect(url_for("index"))

    # GET: show list of patrons
    conn = get_connection()
    patrons = []
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT patron_id, first_name, last_name, email, patron_type, balance
                FROM Patron
                ORDER BY patron_id;
            """)
            patrons = cur.fetchall()
    finally:
        conn.close()

    return render_template("index.html", patrons=patrons)

# -----------------------------
# Example route: show list of books
# -----------------------------
@app.route("/books")
def books():
    conn = get_connection()
    books = []
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT b.isbn, b.title, b.pub_year, p.name AS publisher_name
                FROM Book b
                LEFT JOIN Publisher p ON b.publisher_id = p.publisher_id
                ORDER BY b.title;
            """)
            books = cur.fetchall()
    finally:
        conn.close()

    return render_template("books.html", books=books)

if __name__ == "__main__":
    app.run(debug=True)
