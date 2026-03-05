const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("FuturesMarginPoolModule", (m) => {
  // Define parameters with defaults for local development
  const withdrawAdmin = m.getParameter("withdrawAdmin");
  const admin = m.getParameter("admin");
  const vaults = m.getParameter("vaults");
  const feeAddress = m.getParameter("feeAddress");
  const marginCoinAddress = m.getParameter("marginCoinAddress");

  // Deploy the FuturesMarginPoolClassics contract
  const futuresMarginPool = m.contract("FuturesMarginPoolClassics", [
    withdrawAdmin,
    admin,
    vaults,
    feeAddress,
    marginCoinAddress,
  ]);

  return { futuresMarginPool };
});
