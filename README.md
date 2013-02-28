# RedmineUndevGit

## Описание

Плагин добавляет в редмайн 2 новых возможности:

  - cобственный git-адаптер;
  - хуки;

### UndevGit

Плагин содержит собственный git-адаптер на базе библиотеки grit (её же использует github),
который помимо стандартных вещей, добавляет следующую функциональность:

  - в настройках репозитория можно указывать не только путь к локальному
    каталогу с исходниками, но и ссылку на удалённый репозиторий (git://, https://);

  - репозиторий автоматически обновляется при вызове fetch_changesets;

  - для каждого ченджсета сохраняются ветки;

  - "ключевые слова" (closes, fix и т.п.) обрабатываются глобально для всех
    проектов, т.е. любой коммит может изменять любой тикет редмайна, а не только
    тикеты своего проекта;

  - возможность отключения применения хуков при подключении репозитория

**Особенности**:

В отличии от стандартного адаптера, в UndevGit, чтобы сослаться на коммит, не
нужно использовать ключевые слова (ref keywords). Достаточно просто в комментарии
упомянуть #номер_тикета.

### Хуки

Плагин добавляет такую сущность, как "хук". При помощи хуков возможно гибко
настраивать поведение (выставление статуса, изменение процента готовности)
ключевых слов в зависимости от ветки / проекта, к которым принадлежит ченджсет.
Хуки бывают 3 видов: глобальные, локальные для проекта и локальные для
репозитория.

## Ограничения

 1. Только git, только UTF-8, только Мытищи^W^W только русская и английская локаль.
 2. Не поддерживаются таймлоги.

## Установка

 1. Скопировать каталог с плагином в plugins
 2. bundle exec rake redmine:plugins:migrate
 3. bundle install в / проекта
 4. Перезапустить redmine

## Testing

Creates a test git repository for undev_git
    rake test:scm:setup:undev_git

Prepare test database
    rake RAILS_ENV=test db:drop db:create db:migrate redmine:plugins:migrate

Run tests for redmine_undev_plugin
    rake RAILS_ENV=test NAME=redmine_undev_git redmine:plugins:test


# Версия 2

