const CONTRACT_ADDRESS = "0x61Ce8F8e157AaE4125eEfa7f507837Fb85Ce01E6";

// ── DOM refs ──────────────────────────────────────────────────
const connectBtn   = document.getElementById("connect-btn");
const fundBtn      = document.getElementById("fund-btn");
const withdrawBtn  = document.getElementById("withdraw-btn");
const amountInput  = document.getElementById("eth-amount");
const counterEl    = document.getElementById("eth-counter");
const fundersEl    = document.getElementById("funders-list");
const funderCount  = document.getElementById("funder-count");
const adminSection = document.getElementById("admin-section");

let provider = null;
let signer   = null;
let contract = null;
let balanceInterval = null;

// ── Init on page load ─────────────────────────────────────────
// Balance loads immediately — no wallet connection needed.
// We use window.ethereum as a read-only provider if MetaMask is present.

window.addEventListener("load", async () => {
  if (!window.ethereum) {
    showNoMetaMask();
    return;
  }

  // Read-only: don't prompt the user yet
  const readOnlyProvider = new ethers.BrowserProvider(window.ethereum);
  await updateBalance(readOnlyProvider);
  balanceInterval = setInterval(() => updateBalance(readOnlyProvider), 10_000);

  // Auto-reconnect if the user already approved this site before
  const accounts = await window.ethereum.request({ method: "eth_accounts" });
  if (accounts.length > 0) {
    await setupWallet();
  }
});

// ── Connect wallet ────────────────────────────────────────────
async function connectWallet() {
  if (!window.ethereum) { alert("Please install MetaMask!"); return; }

  try {
    await window.ethereum.request({ method: "eth_requestAccounts" });
    await setupWallet();
  } catch (err) {
    if (err.code !== 4001) console.error("Connection error:", err); // 4001 = user rejected
  }
}

async function setupWallet() {
  provider = new ethers.BrowserProvider(window.ethereum);
  signer   = await provider.getSigner();
  contract = new ethers.Contract(CONTRACT_ADDRESS, abi, signer);

  // Show shortened address on button
  const address = await signer.getAddress();
  connectBtn.textContent = address.slice(0, 6) + "..." + address.slice(-4);
  connectBtn.classList.add("connected");

  // Upgrade polling to use signer's provider (more reliable)
  clearInterval(balanceInterval);
  await updateBalance(provider);
  balanceInterval = setInterval(() => updateBalance(provider), 10_000);

  // Real-time: update the moment a tx is mined — no waiting for the interval
  contract.on("Funded", async () => {
    await updateBalance(provider);
    await loadFunders();
    pulseCounter();
  });

  contract.on("Withdrawn", async () => {
    await updateBalance(provider);
    await loadFunders();
  });

  // Load funders list
  await loadFunders();

  // Show admin panel if this wallet is the owner
  const owner = await contract.getOwner();
  if (owner.toLowerCase() === address.toLowerCase()) {
    adminSection.classList.remove("hidden");
  }
}

// ── Live balance ──────────────────────────────────────────────
// Uses provider.getBalance — works without a signer, no wallet prompt.

async function updateBalance(prov) {
  try {
    const raw       = await prov.getBalance(CONTRACT_ADDRESS);
    const formatted = parseFloat(ethers.formatEther(raw)).toFixed(4) + " ETH";

    if (counterEl.textContent !== formatted) {
      counterEl.textContent = formatted;
      pulseCounter();
    }
  } catch (err) {
    console.error("Balance update failed:", err);
  }
}

// Brief flash animation whenever the counter changes
function pulseCounter() {
  counterEl.classList.remove("pulse");
  void counterEl.offsetWidth; // force reflow so animation restarts
  counterEl.classList.add("pulse");
}

// ── Funders list ──────────────────────────────────────────────
// Deduplicates addresses (same funder can appear multiple times in the array)
// and sorts by total contribution descending.

async function loadFunders() {
  if (!contract) return;

  try {
    const length = Number(await contract.getFundersLength());

    if (length === 0) {
      fundersEl.innerHTML = '<p class="empty">No funders yet. Be the first!</p>';
      funderCount.textContent = "";
      return;
    }

    // Fetch all funder addresses in parallel
    const addressPromises = Array.from({ length }, (_, i) => contract.getFunder(i));
    const addresses = await Promise.all(addressPromises);

    // Deduplicate (case-insensitive)
    const unique = [...new Set(addresses.map(a => a.toLowerCase()))];

    // Fetch each unique address's funded amount in parallel
    const amounts = await Promise.all(unique.map(addr => contract.getAmountFunded(addr)));

    // Sort by amount descending
    const funders = unique
      .map((addr, i) => ({ addr, amount: amounts[i] }))
      .sort((a, b) => (b.amount > a.amount ? 1 : -1));

    funderCount.textContent = `${funders.length} funder${funders.length !== 1 ? "s" : ""}`;
    fundersEl.innerHTML = "";

    funders.forEach(({ addr, amount }, i) => {
      const row = document.createElement("div");
      row.className = "funder-row";
      row.innerHTML = `
        <span class="funder-rank">#${i + 1}</span>
        <span class="funder-addr">${addr.slice(0, 6)}...${addr.slice(-4)}</span>
        <span class="funder-amount">${parseFloat(ethers.formatEther(amount)).toFixed(4)} ETH</span>
      `;
      fundersEl.appendChild(row);
    });

  } catch (err) {
    console.error("Failed to load funders:", err);
  }
}

// ── Fund ──────────────────────────────────────────────────────
async function fund() {
  if (!contract) { alert("Connect your wallet first."); return; }

  const amount = amountInput.value.trim();
  if (!amount || isNaN(amount) || Number(amount) <= 0) {
    alert("Enter a valid ETH amount.");
    return;
  }

  try {
    setBtn(fundBtn, "Sending...", true);

    const tx = await contract.fund({ value: ethers.parseEther(amount) });

    setBtn(fundBtn, "Confirming...", true);
    await tx.wait();

    amountInput.value = "";
    setBtn(fundBtn, "Fund", false);
    // Balance + funders update automatically via the "Funded" event listener above

  } catch (err) {
    console.error(err);
    setBtn(fundBtn, "Fund", false);
    handleTxError(err);
  }
}

// ── Withdraw ──────────────────────────────────────────────────
async function withdraw() {
  if (!contract) return;

  try {
    setBtn(withdrawBtn, "Withdrawing...", true);

    const tx = await contract.withdraw();
    await tx.wait();

    setBtn(withdrawBtn, "Withdraw All Funds", false);
    // Balance + funders update via "Withdrawn" event listener

  } catch (err) {
    console.error(err);
    setBtn(withdrawBtn, "Withdraw All Funds", false);
    handleTxError(err);
  }
}

// ── Helpers ───────────────────────────────────────────────────
function setBtn(btn, text, disabled) {
  btn.textContent = text;
  btn.disabled    = disabled;
}

function handleTxError(err) {
  if (err.code === "ACTION_REJECTED") {
    // User cancelled in MetaMask — no need to alert
    return;
  }
  // Surface the contract's revert reason if available
  const reason = err.reason || err.data?.message || null;
  alert(reason ? `Failed: ${reason}` : "Transaction failed. Check the console for details.");
}

function showNoMetaMask() {
  counterEl.textContent = "—";
  connectBtn.textContent = "Install MetaMask";
  connectBtn.addEventListener("click", () => {
    window.open("https://metamask.io", "_blank");
  });
}

// ── Event listeners ───────────────────────────────────────────
connectBtn.addEventListener("click", connectWallet);
fundBtn.addEventListener("click", fund);
withdrawBtn.addEventListener("click", withdraw);

if (window.ethereum) {
  window.ethereum.on("accountsChanged", () => location.reload());
  window.ethereum.on("chainChanged",    () => location.reload());
}