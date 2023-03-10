require("hardhat-deploy");
require("hardhat-deploy-ethers");

const { networkConfig } = require("../helper-hardhat-config");
const private_key = network.config.accounts[0];
const wallet = new ethers.Wallet(private_key, ethers.provider);
const main = async () => {
  const fileFactory = await ethers.getContractFactory("Filtroller", wallet);
  const file = await fileFactory.deploy();
  await file.deployed();
  console.log("FiltrollerContract deployed to:", file.address);
};

const runMain = async () => {
  try {
    await main();
    process.exit(0);
  } catch (error) {
    console.log(error);
    process.exit(1);
  }
};

runMain();
