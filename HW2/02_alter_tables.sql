alter table product add column shelf_days_life INTEGER;
alter table r_steps drop column image;
alter table r_ingredients alter column amount type numeric(11,2);
alter table recipe add constraint unique_name_of_recipe unique (name);