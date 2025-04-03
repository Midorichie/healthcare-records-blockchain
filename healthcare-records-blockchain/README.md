# Blockchain-Based Healthcare Records

A secure platform for patient records management using NFTs for access control on the Stacks blockchain.

## Overview

This project implements a decentralized healthcare records system that:
- Securely stores patient record metadata on-chain (with actual records stored off-chain)
- Uses NFTs to control healthcare provider access to patient records
- Enables patients to grant and revoke access to their medical data
- Provides tiered access levels (read, write, admin)

## Technology Stack

- Stacks Blockchain
- Clarity Smart Contracts
- Clarinet for local development and testing

## Setup Instructions

1. Install Clarinet:
   ```
   curl -sL https://github.com/hirosystems/clarinet/releases/download/v1.0.5/clarinet-linux-x64.tar.gz | tar xz
   chmod +x ./clarinet
   mv ./clarinet /usr/local/bin
   ```

2. Clone this repository:
   ```
   git clone [repository URL]
   cd healthcare-records-blockchain
   ```

3. Initialize the project:
   ```
   clarinet integrate
   ```

4. Run tests:
   ```
   clarinet test
   ```

## Project Structure

- `contracts/healthcare-records.clar`: Main smart contract
- `tests/`: Test files for each contract function
- `settings/Clarinet.toml`: Project configuration

## Smart Contract Functions

### Patient Management
- `register-patient`: Register a new patient with initial record
- `update-record-hash`: Update a patient's record (patient only)

### Access Control
- `grant-provider-access`: Grant access to a healthcare provider (creates NFT)
- `revoke-provider-access`: Revoke access from a provider
- `check-provider-access`: Check if a provider has access to a patient's records

### Record Management
- `provider-update-record`: Provider updates a patient's record (requires write access)
- `get-patient-data`: Retrieve patient data (only accessible by patient or authorized providers)

## Security Considerations

- All record data is stored off-chain with only hash references on-chain
- Patient information can only be accessed by the patient or authorized healthcare providers
- Access is time-limited with expirations
- Multiple access levels control what actions providers can perform
- NFTs represent access rights and can be easily tracked

## License

MIT
