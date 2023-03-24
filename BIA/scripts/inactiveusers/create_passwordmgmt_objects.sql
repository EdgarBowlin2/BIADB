CREATE TABLE USER_EMAIL_ADDRESSES 
(USERNAME			VARCHAR2(50),
VA_EMAIL_ADDR		        VARCHAR2(60));

CREATE UNIQUE INDEX PK_USER_EMAIL_ADDRESSES ON USER_EMAIL_ADDRESSES(USERNAME);

CREATE OR REPLACE VIEW PASSWORD_EXPIRATION_VW AS
(SELECT USERNAME, EXPIRY_DATE, TRUNC(EXPIRY_DATE - SYSDATE) AS "DAYS_LEFT" FROM DBA_USERS
WHERE EXPIRY_DATE >= SYSDATE AND TRUNC(EXPIRY_DATE - SYSDATE) <= 7);

SELECT pevw.username, ue.va_email_addr, pevw.expiry_date, pevw.days_left FROM PASSWORD_EXPIRATION_VW pevw, USER_EMAIL_ADDRESSES ue
WHERE pevw.username = ue.va_email_addr;

