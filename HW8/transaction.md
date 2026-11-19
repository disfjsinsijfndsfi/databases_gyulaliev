# HW8 — Транзакции и уровни изоляции PostgreSQL

**Тема:** Транзакции, уровни изоляции и точки сохранения в PostgreSQL

## Подготовка базы данных
Для проведения экспериментов были созданы две связанные таблицы:
- accounts (счета клиентов с ограничением CHECK на неотрицательный баланс)
- transactions_log (история операций, связанная внешним ключом с accounts)

```sql
DROP TABLE IF EXISTS transactions_log;
DROP TABLE IF EXISTS accounts;

CREATE TABLE accounts (
    id SERIAL PRIMARY KEY,
    owner_name VARCHAR(50) NOT NULL,
    balance NUMERIC(10, 2) NOT NULL CHECK (balance >= 0)
);

CREATE TABLE transactions_log (
    id SERIAL PRIMARY KEY,
    account_id INT REFERENCES accounts(id),
    amount NUMERIC(10, 2) NOT NULL,
    description VARCHAR(100)
);

INSERT INTO accounts (owner_name, balance) VALUES
('Иван', 1000.00),
('Мария', 2000.00);


```
## Часть 1. Базовые операции с транзакциями

### 1. Транзакция с BEGIN ... COMMIT (фиксация изменений в двух связанных таблицах)

### Сценарий 1.1: Пополнение счёта Ивана на 500 руб.

```sql
BEGIN;

INSERT INTO transactions_log (account_id, amount, description)
VALUES (1, 500.00, 'Пополнение через банкомат');

UPDATE accounts SET balance = balance + 500.00 WHERE id = 1;

COMMIT;

SELECT * FROM accounts ORDER BY id;
SELECT * FROM transactions_log ORDER BY id;

```
**Результат:**
Обе операции выполнились атомарно. Баланс Ивана увеличился с 1000.00 до 1500.00, а в таблице transactions_log появилась связанная запись о пополнении.

![Результат выполнения — 1](screenshots/screen_01.png)
![Результат выполнения — 2](screenshots/screen_02.png)

### Сценарий 1.2: Списание со счёта Марии на 300 руб.

```sql
BEGIN;

INSERT INTO transactions_log (account_id, amount, description)
VALUES (2, -300.00, 'Оплата подписки');

UPDATE accounts SET balance = balance - 300.00 WHERE id = 2;

COMMIT;

SELECT * FROM accounts WHERE id = 2;
SELECT * FROM transactions_log ORDER BY id;

```
**Результат:**
Баланс Марии уменьшился с 2000.00 до 1700.00, а в таблицу transactions_log добавлена вторая запись (-300.00).

![Результат выполнения — 3](screenshots/screen_03.png)
![Результат выполнения — 4](screenshots/screen_04.png)

### 2. Транзакция с ROLLBACK вместо COMMIT (ручной откат изменений)

### Сценарий 2.1: Отмена ошибочного зачисления 1000 руб. Ивану

```sql
BEGIN;

INSERT INTO transactions_log (account_id, amount, description)
VALUES (1, 1000.00, 'Ошибочное зачисление');

UPDATE accounts SET balance = balance + 1000.00 WHERE id = 1;

ROLLBACK;

SELECT * FROM accounts WHERE id = 1;
SELECT * FROM transactions_log ORDER BY id;

```
**Результат:**
После команды ROLLBACK база данных полностью отменила обе операции: баланс Ивана остался на уровне 1500.00, а запись об ошибочном зачислении не попала в таблицу transactions_log.

![Результат выполнения — 5](screenshots/screen_05.png)
![Результат выполнения — 6](screenshots/screen_06.png)

### Сценарий 2.2: Отмена перевода средств между счетами

```sql
BEGIN;

UPDATE accounts SET balance = balance - 500.00 WHERE id = 1;
UPDATE accounts SET balance = balance + 500.00 WHERE id = 2;

ROLLBACK;

SELECT * FROM accounts ORDER BY id;

```
**Результат:**
Оба обновления отменены. Балансы Ивана (1500.00) и Марии (1700.00) остались неизменными.

![Результат выполнения — 7](screenshots/screen_07.png)

### 3. Транзакция с ошибкой (автоматический откат при сбое)

### Сценарий 3.1: Ошибка деления на ноль (division by zero)

```sql
BEGIN;

INSERT INTO transactions_log (account_id, amount, description)
VALUES (1, 200.00, 'Транзакция со сбоем');

UPDATE accounts SET balance = balance + (200 / 0) WHERE id = 1;

COMMIT;

SELECT * FROM accounts WHERE id = 1;
SELECT * FROM transactions_log ORDER BY id;

```
**Результат:**
На втором запросе PostgreSQL выдал ошибку SQL Error [22012]: ERROR: division by zero и перевёл транзакцию в прерванное состояние. При попытке фиксации сервер автоматически откатил всю транзакцию целиком, включая первый успешный запрос INSERT.

![Результат выполнения — 8](screenshots/screen_08.png)
![Результат выполнения — 9](screenshots/screen_09.png)

### Сценарий 3.2: Нарушение ограничения согласованности CHECK (balance >= 0)

```sql
BEGIN;

INSERT INTO transactions_log (account_id, amount, description)
VALUES (1, -5000.00, 'Попытка уйти в минус');

UPDATE accounts SET balance = balance - 5000.00 WHERE id = 1;

COMMIT;

SELECT * FROM accounts WHERE id = 1;

```
**Результат:**
Сработало ограничение согласованности CHECK (SQL Error [23514]). Вся транзакция целиком откатилась, запись не сохранилась, а баланс Ивана остался 1500.00.

![Результат выполнения — 10](screenshots/screen_10.png)
![Результат выполнения — 11](screenshots/screen_11.png)

## Часть 2. Уровни изоляции транзакций

### 1. READ UNCOMMITTED / READ COMMITTED: Проверка «грязного» чтения (Dirty Read)

### Сценарий 1.1: UPDATE без COMMIT в T1 и попытка чтения в T2

```sql
BEGIN TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
UPDATE accounts SET balance = 9999.00 WHERE id = 1;

BEGIN TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT * FROM accounts WHERE id = 1;
COMMIT;

ROLLBACK;

```
**Результат:**
Даже при явном указании уровня READ UNCOMMITTED транзакция T2 увидела старое зафиксированное значение 1500.00, а не 9999.00. В PostgreSQL уровень READ UNCOMMITTED работает идентично READ COMMITTED, поэтому «грязное» чтение невозможно.

![Результат выполнения — 12](screenshots/screen_12.png)
![Результат выполнения — 13](screenshots/screen_13.png)

### Сценарий 1.2: INSERT без COMMIT в T1 и попытка чтения в T2

```sql
BEGIN TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
INSERT INTO accounts (owner_name, balance) VALUES ('Тест', 5000.00);

BEGIN TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT * FROM accounts ORDER BY id;
COMMIT;

ROLLBACK;

```
**Результат:**
Сессия T2 вывела только две зафиксированные строки (Иван и Мария). Неподтверждённая запись из T1 скрыта от других пользователей.

![Результат выполнения — 14](screenshots/screen_14.png)
![Результат выполнения — 15](screenshots/screen_15.png)

### 2. READ COMMITTED: Неповторяющееся чтение (Non-Repeatable Read)

### Сценарий 2.1: Изменение баланса в T2 между двумя запросами SELECT в T1

```sql
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT balance FROM accounts WHERE id = 1;

BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
UPDATE accounts SET balance = 1800.00 WHERE id = 1;
COMMIT;

SELECT balance FROM accounts WHERE id = 1;
COMMIT;

```
**Результат:**
Внутри одной транзакции T1 два одинаковых запроса SELECT вернули разные значения (1500.00 и 1800.00). Произошло неповторяющееся чтение, так как на уровне READ COMMITTED каждый новый запрос внутри транзакции видит свежие подтверждённые данные.

![Результат выполнения — 16](screenshots/screen_16.png)
![Результат выполнения — 17](screenshots/screen_17.png)

### Сценарий 2.2: Изменение имени клиента в T2 между двумя SELECT в T1

```sql
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT owner_name FROM accounts WHERE id = 2;

BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
UPDATE accounts SET owner_name = 'Мария Иванова' WHERE id = 2;
COMMIT;

SELECT owner_name FROM accounts WHERE id = 2;
COMMIT;

```
**Результат:**
Повторный запрос внутри T1 увидел обновлённое имя ('Мария Иванова') после выполнения COMMIT в T2.

![Результат выполнения — 18](screenshots/screen_18.png)
![Результат выполнения — 19](screenshots/screen_19.png)

### 3. REPEATABLE READ: Изоляция снимка и проверка фантомного чтения

### Сценарий 3.1: Проверка, что T1 не видит изменений от T2 до своего завершения

```sql
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT balance FROM accounts WHERE id = 1;

BEGIN;
UPDATE accounts SET balance = 2500.00 WHERE id = 1;
COMMIT;

SELECT balance FROM accounts WHERE id = 1;
COMMIT;

```
**Результат:**
Транзакция T1 работала со снимком данных на момент своего старта (1800.00) и не видела обновление из T2 (2500.00) до самого своего завершения (COMMIT).

![Результат выполнения — 20](screenshots/screen_20.png)
![Результат выполнения — 21](screenshots/screen_21.png)

### Сценарий 3.2: Проверка фантомного чтения через INSERT в T2

```sql
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT * FROM accounts ORDER BY id;

BEGIN;
INSERT INTO accounts (owner_name, balance) VALUES ('Алексей', 3000.00);
COMMIT;

SELECT * FROM accounts ORDER BY id;
COMMIT;

```
**Результат:**
В PostgreSQL уровень REPEATABLE READ защищает не только от неповторяющегося, но и от фантомного чтения. Новая строка ('Алексей'), добавленная в T2, не появилась в выборке T1 до закрытия транзакции.

![Результат выполнения — 22](screenshots/screen_22.png)
![Результат выполнения — 23](screenshots/screen_23.png)

### 4. SERIALIZABLE: Конфликты сериализации и конкурентное обновление

### Сценарий 4.1: Две транзакции вставляют одинаковые данные

```sql
CREATE TABLE IF NOT EXISTS serializable_test (
    id SERIAL PRIMARY KEY,
    value VARCHAR(100) UNIQUE NOT NULL
);

TRUNCATE TABLE serializable_test RESTART IDENTITY;

BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
INSERT INTO serializable_test (value) VALUES ('Тестовая запись');

BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
INSERT INTO serializable_test (value) VALUES ('Тестовая запись');

COMMIT;

ROLLBACK;

SELECT * FROM serializable_test;
```

**Результат:** Две транзакции с уровнем изоляции SERIALIZABLE попытались вставить одинаковое значение. После фиксации T1 вставка T2 завершилась ошибкой `23505` (`duplicate key value violates unique constraint`). В таблице осталась одна строка с текстом «Тестовая запись». Ошибка связана с ограничением `UNIQUE`, а не с ошибкой сериализации `40001`.

![Результат выполнения — 35](screenshots/screen_35.png)
![Результат выполнения — 36](screenshots/screen_36.png)

### Сценарий 4.2: Ошибка конкурентного обновления (concurrent update) и повтор транзакции

```sql
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
UPDATE accounts SET balance = balance + 100.00 WHERE id = 1;

BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
UPDATE accounts SET balance = balance + 200.00 WHERE id = 1;

COMMIT;

ROLLBACK;

BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
UPDATE accounts SET balance = balance + 200.00 WHERE id = 1;
COMMIT;

SELECT * FROM accounts WHERE id = 1;

```
**Результат:**
При одновременном обновлении одной и той же строки (id = 1) после фиксации T1 вторая транзакция прервалась с ошибкой SQL Error [40001]: ERROR: could not serialize access due to concurrent update. После выполнения ROLLBACK и повторного запуска транзакции обновление прошло успешно, и к балансу применились обе операции (итоговый баланс 2300.00).

![Результат выполнения — 24](screenshots/screen_24.png)
![Результат выполнения — 25](screenshots/screen_25.png)
![Результат выполнения — 26](screenshots/screen_26.png)
![Результат выполнения — 27](screenshots/screen_27.png)
![Результат выполнения — 28](screenshots/screen_28.png)
![Результат выполнения — 29](screenshots/screen_29.png)
![Результат выполнения — 30](screenshots/screen_30.png)
![Результат выполнения — 31](screenshots/screen_31.png)

## Часть 3. Точки сохранения (savepoint)

### 1. Одна точка сохранения (частичный откат изменений)

```sql
BEGIN;

UPDATE accounts SET balance = balance + 500.00 WHERE id = 1;
INSERT INTO transactions_log (account_id, amount, description)
VALUES (1, 500.00, 'Пополнение до SAVEPOINT');

SAVEPOINT sp1;

UPDATE accounts SET balance = balance - 1000.00 WHERE id = 1;
INSERT INTO transactions_log (account_id, amount, description)
VALUES (1, -1000.00, 'Ошибочное списание после SAVEPOINT');

ROLLBACK TO SAVEPOINT sp1;

COMMIT;

SELECT * FROM accounts WHERE id = 1;
SELECT * FROM transactions_log ORDER BY id;

```
**Результат:**
Команда ROLLBACK TO SAVEPOINT sp1 отменила только ошибочное списание (-1000.00), выполненное после точки сохранения, но сохранила пополнение (+500.00). Баланс Ивана составил 2800.00.

![Результат выполнения — 32](screenshots/screen_32.png)

### 2. Две точки сохранения (последовательный откат на sp2 и sp1)

```sql
BEGIN;

UPDATE accounts SET balance = balance + 100.00 WHERE id = 1;
SAVEPOINT sp1;

UPDATE accounts SET balance = balance + 200.00 WHERE id = 1;
SAVEPOINT sp2;

UPDATE accounts SET balance = balance + 300.00 WHERE id = 1;

ROLLBACK TO SAVEPOINT sp2;
SELECT balance FROM accounts WHERE id = 1;

ROLLBACK TO SAVEPOINT sp1;
SELECT balance FROM accounts WHERE id = 1;

COMMIT;

```
**Результат:**
Откат до второй точки (sp2) отменил последнее прибавление (+300.00) и вернул баланс к 3100.00. Последующий откат до первой точки (sp1) отменил прибавление (+200.00) и вернул баланс к 2900.00, сохранив самое первое изменение (+100.00).

![Результат выполнения — 33](screenshots/screen_33.png)
![Результат выполнения — 34](screenshots/screen_34.png)

## Выводы

### COMMIT и ROLLBACK
COMMIT сохраняет изменения, а ROLLBACK отменяет их. При ошибке внутри транзакции (например, деление на ноль или нарушение CHECK) транзакция переходит в состояние ошибки. После ROLLBACK изменения не сохраняются.

### Уровни изоляции
- READ UNCOMMITTED в PostgreSQL технически реализован идентично уровню READ COMMITTED и не допускает «грязного» чтения незафиксированных данных других транзакций.
- READ COMMITTED (уровень по умолчанию) защищает от чтения неподтверждённых данных, но допускает неповторяющееся чтение, так как каждый отдельный запрос SELECT внутри транзакции читает самые свежие зафиксированные версии строк.
- REPEATABLE READ фиксирует единый снимок базы данных на момент старта транзакции. На этом уровне транзакция не видит изменений и новых строк (фантомов), зафиксированных параллельными сессиями, до момента своего завершения.
- SERIALIZABLE обеспечивает строгую последовательную изоляцию. При обнаружении перекрёстных зависимостей чтения/записи или попытке конкурентного обновления одной и той же строки (concurrent update) PostgreSQL принудительно прерывает конфликтующую транзакцию с кодом ошибки 40001 (serialization_failure), требуя её повторного выполнения.

### SAVEPOINT
ROLLBACK отменяет всю транзакцию. ROLLBACK TO SAVEPOINT отменяет только изменения после выбранной точки. Изменения до неё остаются и могут быть сохранены через COMMIT.

