# Teenybase

A <small>tiny</small> backend for 🫵 next app.

> Note - this project is in pre-alpha and not suitable for production use. but many things are coming, so stay tuned.

Teenybase is a simple backend framework for javascript, sqlite, edge workers and object storage, written in TypeScript.

This is for making mostly single-file serverless backends for small modules/projects that can be easily deployed and reused. With a simple API, it's possible to extend the framework in any kind of backends.

## Features

- [x] Backend in a file
  - [x] Database Schema in JSON
  - [x] SQL tables
    - [x] Columns
    - [x] Foreign keys
    - [x] File fields
    - [ ] Indexes
    - [ ] Triggers
  - [x] Rules extension
  - [x] Auth extension
  - [x] Crud extension
  - [ ] Database Events/Triggers
  - [ ] Custom routes/proxy mappings
  - [x] Email configuration
    - [x] Mailgun
- [x] CLI and migrations
  - [x] Local development
  - [x] Automatic migrations
    - [x] Create table
    - [x] Drop table
    - [x] Add column
    - [x] Drop column
    - [x] Alter column
    - [ ] Rename table
    - [ ] Rename column
  - [x] Deploy worker
  - [x] Deploy secrets
  - [ ] Static assets/files deployment
  - [ ] Custom Environments from wrangler.toml
- [x] Edge workers
- [x] Object storage (R2, S3)
- [x] SQLite, libSQL, D1
- [x] Row level security - Rule based access control for CRUD
- [x] Deploy on single vendor stack (cloudflare) (-mailgun)
- [x] Local full stack development (-mailgun)
- [x] REST API
  - [x] JSON support
  - [x] JWT authentication
  - [x] Form data support with files
  - [x] CRUD routes with rules
  - [x] Auth routes
  - [x] File access routes
  - [x] OpenAPI spec
  - [x] Swagger UI
  - [ ] Database Events/Triggers
  - [ ] RPC
  - [ ] Static file hosting
- [x] Simple built-in QB/ORM (unified for both backend and frontend)
- [ ] Database Events/Triggers
- [ ] Static assets/files in bucket
- [x] Username/email + password authentication
- [x] Mailgun integration
- [ ] OAuth2 integration
  - [ ] Google
  - [ ] Twitter
  - [ ] Github
  - [ ] Apple
  - [ ] Discord
- [ ] Frontend SDK
- [ ] Frontend components
- [ ] Admin panel UI
- [ ] Rate limiting
- [ ] Cache control
- [ ] CF Cache API
- [ ] Encryption
  - [ ] Column Level
  - [ ] Table Level
  - [ ] Database Level

