-- =========================================================
-- 05_triggers.sql
-- Database triggers to ensure data integrity and business rules
-- (Run after 02_schema_tables.sql and 03_constraints_indexes.sql)
-- =========================================================

USE UniLibPlus;

-- =========================================================
-- 1. Loan Triggers: Prevent double-borrowing and validate dates
-- =========================================================

-- Trigger: Prevent borrowing a copy that is already on loan
-- Business rule: A copy cannot be borrowed if it has an active loan (return_ts IS NULL)
DELIMITER $$

CREATE TRIGGER trg_loan_before_insert
BEFORE INSERT ON Loan
FOR EACH ROW
BEGIN
    DECLARE active_loan_count INT;
    
    -- Check if this copy is already on loan (has an active loan with return_ts IS NULL)
    SELECT COUNT(*) INTO active_loan_count
    FROM Loan
    WHERE copy_id = NEW.copy_id
      AND return_ts IS NULL;
    
    IF active_loan_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot borrow: This copy is already on loan. Please return it first.';
    END IF;
    
    -- Validate that due_ts is after loan_ts
    IF NEW.due_ts <= NEW.loan_ts THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid loan dates: due_ts must be after loan_ts.';
    END IF;
END$$

-- Trigger: Validate return date when updating a loan
-- Business rule: return_ts must be >= loan_ts
CREATE TRIGGER trg_loan_before_update
BEFORE UPDATE ON Loan
FOR EACH ROW
BEGIN
    -- If return_ts is being set, validate it
    IF NEW.return_ts IS NOT NULL THEN
        -- If return_ts is being changed from NULL to a value, validate it
        IF OLD.return_ts IS NULL AND NEW.return_ts < NEW.loan_ts THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid return date: return_ts must be >= loan_ts.';
        END IF;
        
        -- Prevent setting return_ts to NULL if it was already set
        IF OLD.return_ts IS NOT NULL AND NEW.return_ts IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot unset return_ts: Once a loan is returned, it cannot be undone.';
        END IF;
    END IF;
    
    -- Prevent changing copy_id or patron_id after loan is created
    IF OLD.copy_id != NEW.copy_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot change copy_id of an existing loan.';
    END IF;
    
    IF OLD.patron_id != NEW.patron_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot change patron_id of an existing loan.';
    END IF;
END$$

-- =========================================================
-- 2. Fine Triggers: Ensure fines are associated with valid loans
-- =========================================================

-- Trigger: Validate fine creation
-- Business rule: Fine can only be created for a loan that exists
-- (Foreign key already handles this, but we add extra validation)
CREATE TRIGGER trg_fine_before_insert
BEFORE INSERT ON Fine
FOR EACH ROW
BEGIN
    DECLARE loan_exists INT;
    DECLARE loan_patron_id INT;
    
    -- Verify the loan exists
    SELECT COUNT(*), patron_id INTO loan_exists, loan_patron_id
    FROM Loan
    WHERE loan_id = NEW.loan_id;
    
    IF loan_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot create fine: Loan does not exist.';
    END IF;
    
    -- Ensure patron_id matches the loan's patron_id
    IF loan_patron_id != NEW.patron_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Fine patron_id must match the loan patron_id.';
    END IF;
    
    -- Validate amount is positive
    IF NEW.amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Fine amount must be greater than 0.';
    END IF;
    
    -- Validate status
    IF NEW.status NOT IN ('Paid', 'Unpaid', 'Pending', 'Waived') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid fine status. Must be one of: Paid, Unpaid, Pending, Waived.';
    END IF;
END$$

-- =========================================================
-- 3. Reservation Triggers: Prevent duplicate active reservations
-- =========================================================

-- Trigger: Prevent duplicate active reservations
-- Business rule: A patron cannot have multiple active reservations for the same ISBN at the same branch
CREATE TRIGGER trg_reservation_before_insert
BEFORE INSERT ON Reservation
FOR EACH ROW
BEGIN
    DECLARE active_reservation_count INT;
    
    -- Check for active reservations (exclude 'Fulfilled' and 'Cancelled' as they are completed)
    SELECT COUNT(*) INTO active_reservation_count
    FROM Reservation
    WHERE patron_id = NEW.patron_id
      AND isbn = NEW.isbn
      AND branch_id = NEW.branch_id
      AND status NOT IN ('Fulfilled', 'Cancelled');
    
    IF active_reservation_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot create reservation: Patron already has an active reservation for this book at this branch.';
    END IF;
END$$

-- =========================================================
-- 4. AccessSession Triggers: Enforce concurrent access limits
-- =========================================================

-- Trigger: Enforce concurrent access limits for e-resources
-- Business rule: Cannot exceed the concurrent_limit specified in the License
CREATE TRIGGER trg_accesssession_before_insert
BEFORE INSERT ON AccessSession
FOR EACH ROW
BEGIN
    DECLARE current_sessions INT;
    DECLARE max_concurrent INT;
    DECLARE license_id_val INT;
    
    -- Get the license_id for this resource
    SELECT license_id INTO license_id_val
    FROM EResource
    WHERE resource_id = NEW.resource_id;
    
    -- Get the concurrent limit from the license
    SELECT concurrent_limit INTO max_concurrent
    FROM License
    WHERE license_id = license_id_val;
    
    -- Count current active sessions (end_time IS NULL means active)
    SELECT COUNT(*) INTO current_sessions
    FROM AccessSession
    WHERE resource_id = NEW.resource_id
      AND end_time IS NULL;
    
    -- Check if adding this session would exceed the limit
    IF current_sessions >= max_concurrent THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = CONCAT('Cannot create access session: Concurrent access limit (', max_concurrent, ') has been reached for this resource.');
    END IF;
    
    -- Validate start_time
    IF NEW.start_time IS NULL THEN
        SET NEW.start_time = CURRENT_TIMESTAMP;
    END IF;
END$$

-- Trigger: Validate end_time when updating AccessSession
CREATE TRIGGER trg_accesssession_before_update
BEFORE UPDATE ON AccessSession
FOR EACH ROW
BEGIN
    -- If end_time is being set, validate it
    IF NEW.end_time IS NOT NULL THEN
        -- end_time must be >= start_time
        IF NEW.end_time < NEW.start_time THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid end_time: end_time must be >= start_time.';
        END IF;
        
        -- Prevent unsetting end_time
        IF OLD.end_time IS NOT NULL AND NEW.end_time IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot unset end_time: Once a session is ended, it cannot be undone.';
        END IF;
    END IF;
END$$

-- =========================================================
-- 5. Copy Triggers: Validate copy data
-- =========================================================

-- Trigger: Ensure copy belongs to a valid book and branch
-- (Foreign keys already handle this, but we add validation for barcode uniqueness)
CREATE TRIGGER trg_copy_before_insert
BEFORE INSERT ON Copy
FOR EACH ROW
BEGIN
    -- If barcode is provided, it should be unique (already handled by UNIQUE constraint)
    -- Additional validation can be added here if needed
    IF NEW.barcode IS NOT NULL AND NEW.barcode = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Barcode cannot be an empty string. Use NULL if no barcode.';
    END IF;
END$$

-- =========================================================
-- 6. Patron Triggers: Validate patron data
-- =========================================================

-- Trigger: Ensure patron balance is not negative (or enforce business rules)
CREATE TRIGGER trg_patron_before_update
BEFORE UPDATE ON Patron
FOR EACH ROW
BEGIN
    -- Optionally enforce that balance cannot go below a certain threshold
    -- Adjust based on your business rules
    -- For now, we'll allow negative balances (overdraft) but you can change this
    
    -- Validate patron_type if needed
    IF NEW.patron_type NOT IN ('Student', 'Faculty', 'Staff', 'Alumni', 'Guest') THEN
        -- This is a warning, adjust based on your actual patron types
        -- You can make it stricter by using SIGNAL
        -- SIGNAL SQLSTATE '45000'
        -- SET MESSAGE_TEXT = 'Invalid patron_type.';
    END IF;
END$$

-- =========================================================
-- 7. License Triggers: Validate license dates
-- =========================================================

-- Trigger: Ensure license end_date is after start_date
CREATE TRIGGER trg_license_before_insert
BEFORE INSERT ON License
FOR EACH ROW
BEGIN
    IF NEW.end_date <= NEW.start_date THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid license dates: end_date must be after start_date.';
    END IF;
    
    IF NEW.concurrent_limit <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Concurrent limit must be greater than 0.';
    END IF;
END$$

CREATE TRIGGER trg_license_before_update
BEFORE UPDATE ON License
FOR EACH ROW
BEGIN
    IF NEW.end_date <= NEW.start_date THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid license dates: end_date must be after start_date.';
    END IF;
    
    IF NEW.concurrent_limit <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Concurrent limit must be greater than 0.';
    END IF;
END$$

-- =========================================================
-- 8. Term Triggers: Validate term dates
-- =========================================================

-- Trigger: Ensure term end_date is after start_date
CREATE TRIGGER trg_term_before_insert
BEFORE INSERT ON Term
FOR EACH ROW
BEGIN
    IF NEW.start_date IS NOT NULL AND NEW.end_date IS NOT NULL THEN
        IF NEW.end_date <= NEW.start_date THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid term dates: end_date must be after start_date.';
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_term_before_update
BEFORE UPDATE ON Term
FOR EACH ROW
BEGIN
    IF NEW.start_date IS NOT NULL AND NEW.end_date IS NOT NULL THEN
        IF NEW.end_date <= NEW.start_date THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid term dates: end_date must be after start_date.';
        END IF;
    END IF;
END$$

DELIMITER ;

-- =========================================================
-- End of 05_triggers.sql
-- =========================================================

