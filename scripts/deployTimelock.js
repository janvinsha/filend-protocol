const main = async () => {
  const fileFactory = await hre.ethers.getContractFactory("Timelock");
  const file = await fileFactory.deploy(
    //address admin_
    "0x659CE0FC2499E1Fa14d30F5CD88aD058ba490e39",
    //uint delay
    259200 //3days in seconds
  );
  await file.deployed();
  console.log("Timelock deployed to:", file.address);
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
