const main = async () => {
  const filFactory = await hre.ethers.getContractFactory("Fil");
  const fil = await filFactory.deploy(
    //admin_
    "0x659CE0FC2499E1Fa14d30F5CD88aD058ba490e39"
  );
  await fil.deployed();
  console.log("Fil Contract deployed to:", fil.address);
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
