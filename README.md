# UniLibPlus - University Library Management System

A Flask-based web application for managing a university library system with patrons, books, and related database operations.

## Project Structure

```
UniLib/
├── app.py                      # Main Flask application
├── requirements.txt            # Python dependencies
├── templates/                  # HTML templates
│   ├── index.html             # Patrons management page
│   └── books.html             # Books listing page
├── create_database.sql         # Database creation script
├── schema_tables.sql           # Table schema definitions
├── constraints_indexes.sql     # Constraints and indexes
├── data.sql                    # Sample data
├── views.sql                   # Database views
└── queries_examples.sql        # Example SQL queries
```

## Features

- **Patron Management**: View and add library patrons
- **Book Catalog**: Browse library books with publisher information
- **Database Integration**: Connects to MySQL database via SSH tunnel

## Prerequisites

- Python 3.8 or higher
- MySQL database (hosted on remote server)
- SSH access to the database server
- Flask and PyMySQL packages

## Installation

1. **Clone or navigate to the project directory:**
   ```bash
   cd /path/to/UniLib
   ```

2. **Install Python dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

   Or install manually:
   ```bash
   pip install Flask>=3.0.0 PyMySQL>=1.0.0
   ```

3. **Set up the database:**
   - Connect to your MySQL server
   - Run the SQL scripts in order:
     ```bash
     mysql -u root -p < create_database.sql
     mysql -u root -p UniLibPlus < schema_tables.sql
     mysql -u root -p UniLibPlus < constraints_indexes.sql
     mysql -u root -p UniLibPlus < data.sql
     mysql -u root -p UniLibPlus < views.sql
     ```

## Configuration

The database connection is configured in `app.py`. Update the following settings if needed:

```python
host="localhost"        # MySQL host (localhost when using SSH tunnel)
port=3307              # Local port forwarded from remote MySQL
user="root"            # MySQL username
password="your_password"  # MySQL password
database="UniLibPlus"  # Database name
```

## Running the Application

### Step 1: Establish SSH Tunnel

Before starting the Flask app, you need to create an SSH tunnel to forward the remote MySQL port to your local machine:

```bash
ssh -R 3307:localhost:3306 your_netid@server_address
```

**Explanation:**
- `-R 3307:localhost:3306` creates a reverse tunnel
  - `3307` is the local port on your machine
  - `localhost:3306` is the remote MySQL server (accessible from the remote server)
- `your_netid@server_address` is your SSH credentials and server address

**Note:** Keep this SSH session open while running the Flask application.

### Step 2: Start the Flask Application

In a new terminal window:

```bash
python3 app.py
```

Or:

```bash
python app.py
```

The application will start in debug mode and display:
```
 * Serving Flask app 'app'
 * Debug mode: on
 * Running on http://127.0.0.1:5000
```

### Step 3: Access the Application

Open your web browser and navigate to:

```
http://127.0.0.1:5000/
```

## Available Routes

- **`/`** (GET/POST): Main page displaying patrons list and form to add new patrons
- **`/books`** (GET): Page displaying all books with publisher information

## Troubleshooting

### Connection Refused Error

If you see `ConnectionRefusedError` or `Can't connect to MySQL server`:

1. **Check SSH tunnel:** Ensure the SSH tunnel is active and running
   ```bash
   # In another terminal, check if port 3307 is listening
   netstat -an | grep 3307
   # or
   ss -tuln | grep 3307
   ```

2. **Verify MySQL is running on remote server:** Log into the remote server and check:
   ```bash
   ssh your_netid@server_address
   systemctl status mysql
   # or
   systemctl status mysqld
   ```

3. **Check database credentials:** Verify username, password, and database name in `app.py`

4. **Port conflict:** If port 3307 is already in use, change it in both:
   - SSH command: `ssh -R NEW_PORT:localhost:3306 ...`
   - `app.py`: `port=NEW_PORT`

### Import Errors

If you see import errors for Flask or PyMySQL:

1. Ensure you're using the correct Python environment
2. Reinstall dependencies: `pip install -r requirements.txt`
3. Check Python version: `python3 --version` (should be 3.8+)

## Development

- **Debug Mode:** Enabled by default in `app.py` (line 91)
- **Auto-reload:** Flask will automatically reload when code changes are detected
- **Database Queries:** See `queries_examples.sql` for example SQL queries

## Notes

- The SSH tunnel must remain active while the application is running
- Database password is stored in plain text in `app.py` (consider using environment variables for production)
- The application uses Flask's development server (not suitable for production deployment)

## License

This project is part of a university coursework assignment.

