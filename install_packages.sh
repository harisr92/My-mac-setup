echo "Installing default packages";

for i in $(cat my_packages.txt); do;
  echo "Hello $i";
done;
