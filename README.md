# IT-Agent: Employee Termination Automation

Automated employee termination workflow using n8n, PowerShell, Microsoft Graph, Exchange Online, and Active Directory.

## 🎯 Project Overview

This project implements a fully automated employee termination process that:
- Converts M365 mailboxes to shared type
- Removes all M365 licenses
- Grants supervisor mailbox access
- Disables Active Directory accounts
- Removes all group memberships
- Moves users to disabled OU
- Triggers Azure AD sync

**Architecture**: n8n (Linux/Kubernetes) → SSH → Windows Domain Controller → PowerShell Script

---

## 📚 Documentation

All documentation is organized in the [`docs/`](docs/) directory:

### 🚀 **Quick Start: SSH Implementation**

**Start here for deployment**: [`docs/ssh-implementation/`](docs/ssh-implementation/)

Follow these guides in order (~70 minutes total):

1. **[SSH-IMPLEMENTATION-SUMMARY.md](docs/ssh-implementation/SSH-IMPLEMENTATION-SUMMARY.md)** - 📋 Complete overview (read first!)
2. **[PRE-IMPLEMENTATION-CHECKLIST.md](docs/ssh-implementation/PRE-IMPLEMENTATION-CHECKLIST.md)** - ✅ Prerequisites (10 min)
3. **[SSH-CONFIGURATION.md](docs/ssh-implementation/SSH-CONFIGURATION.md)** - 🔧 SSH setup (20 min)
4. **[PS-SCRIPT-DC-DEPLOYMENT.md](docs/ssh-implementation/PS-SCRIPT-DC-DEPLOYMENT.md)** - 📦 Script deployment (15 min)
5. **[N8N-SSH-CREDENTIALS-GUIDE.md](docs/ssh-implementation/N8N-SSH-CREDENTIALS-GUIDE.md)** - 🔑 n8n credentials (5 min)
6. **[N8N-WORKFLOW-SSH-UPDATE.md](docs/ssh-implementation/N8N-WORKFLOW-SSH-UPDATE.md)** - 🔄 Workflow update (15 min)
7. **[TESTING-VALIDATION-GUIDE.md](docs/ssh-implementation/TESTING-VALIDATION-GUIDE.md)** - 🧪 Testing (30 min)

### 📖 **Other Documentation**

- **[Implementation Guides](docs/implementation-guides/)** - Original workflow design documentation
- **[Status Reports](docs/status-reports/)** - Implementation progress tracking
- **[Infrastructure](docs/infrastructure/)** - n8n server setup and troubleshooting

Full documentation index: **[docs/README.md](docs/README.md)**

---

## 🏗️ Architecture

### Current Implementation (SSH-Based)

```
┌─────────────────────────┐
│ n8n (Linux Container)   │
│ Azure Kubernetes (AKS)  │
└───────────┬─────────────┘
            │
            │ SSH (Port 22)
            │ Private Key Auth
            │
┌───────────▼─────────────┐
│ Windows Domain          │
│ Controller              │
│ ┌─────────────────────┐ │
│ │ OpenSSH Server      │ │
│ └──────────┬──────────┘ │
│            │             │
│ ┌──────────▼──────────┐ │
│ │ Terminate-          │ │
│ │ Employee.ps1        │ │
│ └─────────────────────┘ │
│                         │
│ • Active Directory      │
│ • Microsoft Graph       │
│ • Exchange Online       │
└─────────────────────────┘
```

**Why SSH?**
- n8n runs in Linux container (can't execute Windows PowerShell directly)
- SSH enables remote execution on Windows DC
- Zero additional cost, uses existing infrastructure
- Secure with SSH key authentication

---

## 🔧 Prerequisites

### Infrastructure
- Windows Domain Controller with:
  - Active Directory
  - PowerShell 5.1+
  - Modules: Microsoft.Graph, ExchangeOnlineManagement, ActiveDirectory
- n8n instance (running in Kubernetes/AKS)
- Network connectivity between n8n and DC

### Azure AD Setup
- Azure AD App Registration with:
  - Application (client) ID
  - Tenant ID
  - Certificate for authentication
- Permissions:
  - User.ReadWrite.All
  - Directory.ReadWrite.All
  - Group.ReadWrite.All
  - Exchange.ManageAsApp

---

## 📦 What's Included

```
IT-Agent/
├── docs/                           # All documentation (organized)
│   ├── README.md                   # Documentation index
│   ├── ssh-implementation/         # SSH setup guides (main implementation)
│   ├── implementation-guides/      # Original workflow documentation
│   ├── status-reports/             # Progress tracking
│   └── infrastructure/             # Server setup docs
│
├── PRPs/                           # Project Requirement Proposals
│   └── employee-termination-workflow-enhanced.md
│
├── .claude/                        # Claude Code configuration
│   ├── commands/                   # Custom slash commands
│   └── agents/                     # Specialized subagents
│
├── CLAUDE.md                       # Project instructions for Claude
└── README.md                       # This file
```

---

## 🚀 Getting Started

### For New Deployments

1. **Read the overview**:
   ```bash
   cat docs/ssh-implementation/SSH-IMPLEMENTATION-SUMMARY.md
   ```

2. **Follow the implementation guides** in the ssh-implementation folder (in order)

3. **Test thoroughly** using the validation guide

### For Existing Deployments

- **Troubleshooting**: Check [docs/infrastructure/](docs/infrastructure/)
- **Status Updates**: Review [docs/status-reports/](docs/status-reports/)
- **Workflow Changes**: See [docs/ssh-implementation/N8N-WORKFLOW-SSH-UPDATE.md](docs/ssh-implementation/N8N-WORKFLOW-SSH-UPDATE.md)

---

## 🔐 Security Considerations

- SSH private keys stored securely in n8n credentials
- Certificate-based authentication for Azure AD
- OpenSSH Server with key-only authentication
- Audit logging enabled for all operations
- Regular key rotation (90-180 days recommended)

---

## 🧪 Testing

Complete testing guide available: [docs/ssh-implementation/TESTING-VALIDATION-GUIDE.md](docs/ssh-implementation/TESTING-VALIDATION-GUIDE.md)

**Test phases**:
1. Component testing (SSH, PowerShell, certificates)
2. Script testing (with invalid/valid employee IDs)
3. n8n workflow testing (manual and webhook triggers)
4. Test user scenarios (full termination process)
5. Error scenario testing
6. Performance testing

---

## 📊 Project Status

**Current Phase**: Documentation complete, ready for implementation

**Implementation Status**:
- ✅ Documentation created (8 comprehensive guides)
- ✅ Architecture designed (SSH-based approach)
- ✅ Testing procedures documented
- ⏳ Pending: SSH setup on DC
- ⏳ Pending: Workflow deployment to n8n
- ⏳ Pending: End-to-end testing

For detailed status: [docs/status-reports/IMPLEMENTATION-STATUS-UPDATED.md](docs/status-reports/IMPLEMENTATION-STATUS-UPDATED.md)

---

## 🛠️ Technology Stack

- **Orchestration**: n8n (workflow automation)
- **Execution**: PowerShell 5.1+
- **Infrastructure**: Azure Kubernetes Service (AKS)
- **Authentication**: OpenSSH, Certificate-based auth
- **Integrations**:
  - Microsoft Graph API
  - Exchange Online PowerShell
  - Active Directory PowerShell

---

## 📝 Maintenance

### Regular Tasks

**Weekly**:
- Review n8n execution logs
- Monitor SSH connection success rate

**Monthly**:
- Test with test user
- Verify certificate expiration date

**Quarterly**:
- Rotate SSH keys
- Update PowerShell modules
- Review and optimize script

---

## 🆘 Support

### Common Issues

| Issue | Documentation |
|-------|---------------|
| SSH connection fails | [SSH-CONFIGURATION.md](docs/ssh-implementation/SSH-CONFIGURATION.md#troubleshooting-guide) |
| PowerShell script errors | [PS-SCRIPT-DC-DEPLOYMENT.md](docs/ssh-implementation/PS-SCRIPT-DC-DEPLOYMENT.md#phase-6-troubleshooting) |
| n8n workflow issues | [N8N-WORKFLOW-SSH-UPDATE.md](docs/ssh-implementation/N8N-WORKFLOW-SSH-UPDATE.md#troubleshooting) |
| n8n server problems | [N8N-SERVER-FIX-GUIDE.md](docs/infrastructure/N8N-SERVER-FIX-GUIDE.md) |

### Getting Help

1. Check relevant guide's troubleshooting section
2. Review [TESTING-VALIDATION-GUIDE.md](docs/ssh-implementation/TESTING-VALIDATION-GUIDE.md#troubleshooting-quick-reference)
3. See [SSH-IMPLEMENTATION-SUMMARY.md](docs/ssh-implementation/SSH-IMPLEMENTATION-SUMMARY.md#common-issues-and-solutions)

---

## 🤝 Contributing

This project uses [Archon](https://github.com/coleam00/Archon) for AI-assisted development with task management and knowledge base integration.

### Development Workflow

Managed through Archon MCP server:
- Project: "SSH PowerShell Execution for n8n"
- Tasks tracked with status: `todo` → `doing` → `review` → `done`
- All 8 implementation guides created and completed

---

## 📄 License

[Add your license here]

---

## 📞 Contact

[Add contact information]

---

**Last Updated**: 2025-10-28
**Version**: 1.0 - SSH Implementation Documentation Complete
