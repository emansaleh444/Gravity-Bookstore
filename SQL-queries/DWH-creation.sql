CREATE DATABASE project_datawarehouse

USE project_datawarehouse;
GO
CREATE TABLE dim_book
(
    book_sk INT IDENTITY(1,1),
    book_id INT,
    title VARCHAR(400),
    isbn13 VARCHAR(13),
    num_pages INT,
    publication_date DATE,
	language_code VARCHAR(8),
    language_name VARCHAR(50),
    publisher_name VARCHAR(400),
    author_name VARCHAR(400),
	start_date DATETIME NOT NULL,
	end_date DATETIME ,
	is_current TINYINT NOT NULL DEFAULT 1,
	PRIMARY KEY (book_sk)
);

CREATE TABLE dim_customer(
     customer_sk INT IDENTITY(1,1),
     customer_id INT,
	 first_name VARCHAR(200),
	 last_name VARCHAR(200),
	 email VARCHAR(350),
	 address_status VARCHAR(30),
	 city VARCHAR(100),
	 country VARCHAR(200),
	 start_date DATETIME NOT NULL,
	 end_date DATETIME ,
	 is_current TINYINT NOT NULL DEFAULT 1,
	 PRIMARY KEY (customer_sk)
);

CREATE TABLE dim_shipping(
      method_sk INT IDENTITY(1,1),
      method_id INT,
	  shipping_method VARCHAR(100),
	  start_date DATETIME NOT NULL,
	  end_date DATETIME ,
	  is_current TINYINT NOT NULL DEFAULT 1,
	  PRIMARY KEY (method_sk)
)


CREATE TABLE dim_status
(
      status_sk INT IDENTITY(1,1),
	  order_status_id INT,
	  order_status VARCHAR(20),
	  PRIMARY KEY (status_sk)
)


CREATE TABLE fact_book_sales(
      order_id_sk INT IDENTITY(1,1),
	  order_id INT,
	  customer_sk INT NOT NULL,
	  book_sk INT NOT NULL,
	  shipping_sk INT NOT NULL,
	  date_sk INT NOT NULL,
	  status_sk INT NOT NULL,

	  total_price decimal,
	  shipping_cost decimal,
	  quantity_sold INT
)

 