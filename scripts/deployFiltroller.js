const main = async () => {
  const fileFactory = await hre.ethers.getContractFactory("Filtroller");
  const file = await fileFactory.deploy();
  await file.deployed();
  console.log("FiletrollerContract deployed to:", file.address);
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
