create table product (product_id INTEGER primary key, name VARCHAR(45) not null);
CREATE TYPE recipe_category AS ENUM ('Закуски', 'Горячее', 'Десерты', 'Салаты');
CREATE TYPE recipe_time AS ENUM ('Быстро', 'Средне', 'Долго');
CREATE TYPE recipe_level AS ENUM ('Легкий', 'Средний', 'Сложный');
CREATE TYPE recipe_type AS ENUM ('Первое', 'Второе', 'Выпечка', 'Напиток');
create table recipe (id INTEGER primary key, name VARCHAR(45) not null, category recipe_category, time_f_p recipe_time, level recipe_level, type recipe_type);
create table r_steps (id INTEGER primary key references recipe(id) on delete cascade, title VARCHAR(45), content TEXT, image VARCHAR(45), steps TEXT);
create table r_ingredients (r_id INTEGER references recipe(id) on delete  cascade, product INTEGER references product(product_id) on delete restrict, amount INTEGER not null, amount_type VARCHAR(45), primary key (r_id, product));