const main = async () => {
  const wpirmFactory = await hre.ethers.getContractFactory(
    "WhitePaperInterestRateModel"
  );
  const wpirm = await wpirmFactory.deploy(
    //base rate
    "50000000000000000",
    //multiplier
    "120000000000000000"
  );
  await wpirm.deployed();
  console.log("white paper interest rate model deployed to:", wpirm.address);
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
