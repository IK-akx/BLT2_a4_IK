// Конфигурация — замени на свои адреса после деплоя
const TOKEN_ADDRESS = '0xYOUR_TOKEN_ADDRESS';
const GOVERNOR_ADDRESS = '0xYOUR_GOVERNOR_ADDRESS';

let TOKEN_ABI, GOVERNOR_ABI;
let provider, signer, tokenContract, governorContract, userAddress;

// Загружаем ABI из файлов
async function loadABIs() {
    try {
        const tokenResponse = await fetch('GovernanceToken.abi.json');
        TOKEN_ABI = await tokenResponse.json();

        const governorResponse = await fetch('MyGovernor.abi.json');
        GOVERNOR_ABI = await governorResponse.json();

        console.log('ABIs loaded successfully');
    } catch (err) {
        console.error('Failed to load ABIs:', err);
        throw err;
    }
}

// ==================== WALLET ====================
async function connectWallet() {
    if (!window.ethereum) {
        alert('Please install MetaMask!');
        return;
    }

    try {
        // Загружаем ABI перед подключением (если еще не загружены)
        if (!TOKEN_ABI || !GOVERNOR_ABI) {
            await loadABIs();
        }

        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        userAddress = accounts[0];

        provider = new ethers.BrowserProvider(window.ethereum);
        signer = await provider.getSigner();

        tokenContract = new ethers.Contract(TOKEN_ADDRESS, TOKEN_ABI, signer);
        governorContract = new ethers.Contract(GOVERNOR_ADDRESS, GOVERNOR_ABI, signer);

        document.getElementById('walletAddress').textContent = userAddress;
        document.getElementById('status').className = 'connected';
        document.getElementById('status').textContent = '🟢 Connected: ' + userAddress.slice(0, 6) + '...' + userAddress.slice(-4);
        document.getElementById('connectBtn').disabled = true;

        await updateTokenInfo();

        window.ethereum.on('accountsChanged', () => location.reload());
        window.ethereum.on('chainChanged', () => location.reload());
    } catch (err) {
        console.error(err);
        alert('Connection failed: ' + err.message);
    }
}

// ==================== TOKEN INFO ====================
async function updateTokenInfo() {
    try {
        const balance = await tokenContract.balanceOf(userAddress);
        const votes = await tokenContract.getVotes(userAddress);
        const delegate = await tokenContract.delegates(userAddress);

        document.getElementById('tokenBalance').textContent = ethers.formatEther(balance) + ' GOV';
        document.getElementById('votingPower').textContent = ethers.formatEther(votes) + ' votes';
        document.getElementById('currentDelegate').textContent =
            delegate.toLowerCase() === userAddress.toLowerCase() ? 'Self' : delegate;
    } catch (err) {
        console.error('Error updating token info:', err);
    }
}

// ==================== DELEGATION ====================
async function delegateVotes() {
    const address = document.getElementById('delegateAddress').value;
    if (!ethers.isAddress(address)) {
        alert('Invalid address');
        return;
    }

    try {
        const tx = await tokenContract.delegate(address);
        document.getElementById('delegateResult').innerHTML =
            `Delegating... <a class="tx-link" href="https://sepolia.etherscan.io/tx/${tx.hash}" target="_blank">View tx</a>`;
        await tx.wait();
        document.getElementById('delegateResult').textContent = 'Delegation successful!';
        await updateTokenInfo();
    } catch (err) {
        document.getElementById('delegateResult').textContent = 'Error: ' + err.message;
    }
}

async function delegateToSelf() {
    try {
        const tx = await tokenContract.delegate(userAddress);
        document.getElementById('delegateResult').innerHTML =
            `Delegating to self... <a class="tx-link" href="https://sepolia.etherscan.io/tx/${tx.hash}" target="_blank">View tx</a>`;
        await tx.wait();
        document.getElementById('delegateResult').textContent = 'Self-delegation successful!';
        await updateTokenInfo();
    } catch (err) {
        document.getElementById('delegateResult').textContent = 'Error: ' + err.message;
    }
}

// ==================== PROPOSALS ====================
const STATE_NAMES = ['Pending', 'Active', 'Canceled', 'Defeated', 'Succeeded', 'Queued', 'Expired', 'Executed'];
const STATE_CLASSES = ['', 'active', '', 'defeated', 'succeeded', '', '', ''];

async function loadProposal() {
    const proposalId = document.getElementById('proposalIdInput').value;
    if (proposalId === '') {
        alert('Enter proposal ID');
        return;
    }

    try {
        const state = await governorContract.state(proposalId);
        const stateName = STATE_NAMES[Number(state)];

        let html = `<div class="proposal ${STATE_CLASSES[Number(state)]}">`;
        html += `<strong>Proposal #${proposalId}</strong> — State: <strong>${stateName}</strong>`;

        // Proposal votes
        try {
            const proposalVotes = await governorContract.proposalVotes(proposalId);
            html += `<br><span style="color:#3fb950;">For: ${ethers.formatEther(proposalVotes.forVotes)}</span>`;
            html += ` | <span style="color:#f85149;">Against: ${ethers.formatEther(proposalVotes.againstVotes)}</span>`;
            html += ` | <span style="color:#8b949e;">Abstain: ${ethers.formatEther(proposalVotes.abstainVotes)}</span>`;
        } catch (e) {
            // votes not yet available
        }

        // Voting buttons (only if Active)
        if (Number(state) === 1) {
            html += '<div class="vote-btns">';
            html += '<button onclick="castVote(' + proposalId + ', 1)">✅ For</button>';
            html += '<button class="danger" onclick="castVote(' + proposalId + ', 0)">❌ Against</button>';
            html += '<button onclick="castVote(' + proposalId + ', 2)">⚪ Abstain</button>';
            html += '</div>';
        }

        html += '</div>';

        document.getElementById('proposalList').innerHTML = html;
    } catch (err) {
        document.getElementById('proposalList').innerHTML =
            '<p style="color:#f85149;">Proposal not found or error: ' + err.message + '</p>';
    }
}

async function castVote(proposalId, voteType) {
    try {
        const tx = await governorContract.castVote(proposalId, voteType);
        document.getElementById('proposalList').innerHTML +=
            `<p>Vote submitted! <a class="tx-link" href="https://sepolia.etherscan.io/tx/${tx.hash}" target="_blank">View tx</a></p>`;
        await tx.wait();
        loadProposal();
    } catch (err) {
        document.getElementById('proposalList').innerHTML +=
            '<p style="color:#f85149;">Vote error: ' + err.message + '</p>';
    }
}