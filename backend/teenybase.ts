import {DatabaseSettings, sqlValue, TableAuthExtensionData, TableData, TableRulesExtensionData} from "teenybase"
import {authFields, baseFields, createdTrigger} from "teenybase/scaffolds/fields";

// Sample tables for reference, remove/edit them based on your needs.

const userTable: TableData = {
    name: "users",
    // r2Base: "users",
    autoSetUid: true, // automatically set the uid to a random uuidv4
    fields: [
        ...baseFields, // id, created, updated
        ...authFields, // username, email, email_verified, password, password-salt, name, avatar, role, meta
    ],
    indexes: [{fields: "role COLLATE NOCASE"}],
    extensions: [
        {
            name: "rules",
            listRule: "(auth.uid == id) | auth.role ~ '%admin' | meta->>'$.pvt'!=true",
            viewRule: "(auth.uid == id) | auth.role ~ '%admin'",
            createRule: "(auth.uid == null & role == 'guest') | (auth.role ~ '%admin' & role != 'superadmin')",
            updateRule: "(auth.uid == id & role == new.role & meta == new.meta) | (auth.role ~ '%admin' & new.role != 'superadmin' & (role != 'superadmin' | auth.role = 'superadmin'))",
            deleteRule: "auth.role ~ '%admin' & role !~ '%admin'",
        } as TableRulesExtensionData,
        {
            name: "auth",
            passwordType: "sha256",
            passwordCurrentSuffix: "Current",
            passwordConfirmSuffix: "Confirm",
            jwtSecret: "$JWT_SECRET_USERS",
            jwtTokenDuration: 3 * 60 * 60, // 3 hours
            maxTokenRefresh: 4, // 12 hours
            emailTemplates: {
                verification: {
                    variables: {
                        message_title: 'Email Verification',
                        message_description: 'Welcome to {{APP_NAME}}. Click the button below to verify your email address.',
                        message_footer: 'If you did not request this, please ignore this email.',
                        action_text: 'Verify Email',
                        action_link: '{{APP_URL}}#/verify-email/{{TOKEN}}',
                    }
                },
                passwordReset: {
                    variables: {
                        message_title: 'Password Reset',
                        message_description: 'Click the button below to reset the password for your {{APP_NAME}} account.',
                        message_footer: 'If you did not request this, you can safely ignore this email.',
                        action_text: 'Reset Password',
                        action_link: '{{APP_URL}}#/reset-password/{{TOKEN}}',
                    }
                }
            }
        } as TableAuthExtensionData,
    ],
    triggers: [
        createdTrigger, // raises an error if created column is updated (optional)
    ],
}

const notesTable: TableData = {
    name: "notes",
    autoSetUid: true, // automatically set the uid to a random uuidv4
    fields: [
        ...baseFields,
        {name: "owner_id", type: "relation", sqlType: "text", notNull: true, foreignKey: {table: "users", column: "id"}},
        {name: "title", type: "text", sqlType: "text", notNull: true},
        {name: "content", type: "editor", sqlType: "text", notNull: true},
        {name: "is_public", type: "bool", sqlType: "boolean", notNull: true, default: sqlValue(false)},
        {name: "slug", type: "text", sqlType: "text", unique: true, notNull: true, noUpdate: true},
        {name: "tags", type: "text", sqlType: "text"},
        {name: "meta", type: "json", sqlType: "json"},
        {name: "cover", type: "file", sqlType: "text"},
        {name: "views", type: "number", sqlType: "integer", noUpdate: true, noInsert: true, default: sqlValue(0)},
        {name: "archived", type: "bool", sqlType: "boolean", noInsert: true, default: sqlValue(false)},
        {name: "deleted_at", type: "date", sqlType: "timestamp", noInsert: true, default: sqlValue(null)},
    ],
    fullTextSearch: {
        fields: ["title", "content", "tags"],
        tokenize: "trigram"
    },
    indexes: [
        {fields: "owner_id"},
        {fields: "tags COLLATE NOCASE"}, // collate nocase so that like search which is case-insensitive uses the index
        {fields: "is_public"},
        {fields: "archived"},
        {fields: "deleted_at"},
    ],
    extensions: [
        {
            name: "rules",
            // Can view if note is public or if user owns it or is admin
            viewRule: "(is_public = true & !deleted_at & !archived) | auth.role ~ '%admin' | (auth.uid != null & owner_id == auth.uid)",
            // Cannot list if note is public but can list if user owns it or is admin
            // todo add count limit
            listRule: "(is_public & !deleted_at & !archived) | auth.role ~ '%admin' | (auth.uid != null & owner_id == auth.uid)",
            // Can create if authenticated and setting self as owner
            createRule: "auth.uid != null & owner_id == auth.uid",
            // Can update if owner and not changing ownership
            updateRule: "auth.uid != null & owner_id == auth.uid & owner_id = new.owner_id",
            // Can delete if owner or admin
            deleteRule: "auth.role ~ '%admin' | (auth.uid != null & owner_id == auth.uid)",
        } as TableRulesExtensionData,
    ],
    triggers: [
        // raise an error if created column is updated (optional)
        createdTrigger,
    ],
}

const kvStoreTable: TableData = {
    name: "kv_store",
    autoSetUid: false,
    fields: [
        {name: "key", type: "text", sqlType: "text", notNull: true, primary: true},
        {name: "value", type: "json", sqlType: "json", notNull: true},
        {name: "expire", type: "date", sqlType: "timestamp"},
    ],
    extensions: [],
}

export default {
    tables: [userTable, notesTable, kvStoreTable],
    appName: "Sample app",
    appUrl: "https://sample.example.com",
    jwtSecret: "$JWT_SECRET_MAIN",

    email: {
        from: "Sender Name <noreply@example.com>",
        tags: ["tag-1"],
        variables: {
            company_name: "Company",
            company_copyright: "Company",
            company_address: "Company address",
            support_email: "support@example.com",
            company_url: "https://example.com",
        },
        mailgun: {
            MAILGUN_API_SERVER: "mail.example.com",
            // MAILGUN_API_URL: "https://api.mailgun.net/v3/"
            MAILGUN_API_KEY: "$MAILGUN_API_KEY",
            MAILGUN_WEBHOOK_SIGNING_KEY: "$MAILGUN_WEBHOOK_SIGNING_KEY",
            MAILGUN_WEBHOOK_ID: "notes-app",
            DISCORD_MAILGUN_NOTIFY_WEBHOOK: "xxxxxxxxx"
            // EMAIL_BLOCKLIST: "a.com,b.com" // comma separated list of domains
        },
    },
} satisfies DatabaseSettings