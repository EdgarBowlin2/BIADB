DROP DATABASE LINK "&1";

CREATE DATABASE LINK "&1"
    CONNECT TO LINKS_RO IDENTIFIED BY "&2"
    USING '(DESCRIPTION=
                (ADDRESS=(PROTOCOL=TCP)(HOST=&3)(PORT=&4))
                (CONNECT_DATA=(SERVICE_NAME=&5))
            )';