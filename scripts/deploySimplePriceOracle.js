const main = async () => {
  const spoFactory = await hre.ethers.getContractFactory("SimplePriceOracle");
  const spo = await spoFactory.deploy();
  await spo.deployed();
  console.log("SimplePriceOracleContract deployed to:", spo.address);
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
