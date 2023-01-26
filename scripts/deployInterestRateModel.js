const main = async () => {
  const imrFactory = await hre.ethers.getContractFactory(
    "WhitePaperInterestRateModel"
  );
  const imr = await imrFactory.deploy(2, 1);
  await imr.deployed();
  console.log("InterestRateModelContract deployed to:", imr.address);
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
