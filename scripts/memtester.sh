#!/bin/sh
runtime=172800

nowpath=$(cd `dirname $0`;pwd)
cd "$nowpath"

compute_test_size()
{
	Cpu_Num=`cat /proc/cpuinfo | grep processor | wc -l`
	Mem_Size=`free -k |awk '/Mem/ {print $4}' `
	
	perCPU=`echo " $Mem_Size / $Cpu_Num" | bc`
	perCPU_MB=`echo "$perCPU / 1024" | bc`
	###set the usage of mem in byte###
	perCPU_use=$(($perCPU_MB*95/100))
}

if test -d ./mem_result
then
	rm -rf ./mem_result
fi
mkdir ./mem_result
####Test whether Memtester be installed####
if ! test -d ./memtester-4.6.0
then
	echo '***********no memtester found !*************' >&2
	exit 1
fi
cd memtester-4.6.0
./memtester > /dev/null 2>&1
###if not installed###
if [ "$?" -eq 127 ] 
then
	echo "Memtester is not be installed. Now try install"
	if ! make
	then
		echo "**********Failed to install memtester!*************"
		exit 1
	fi
	make install
	./memtester 2> /dev/null
	if [ "$?" -eq 127 ] 
	then 
		echo "**********Failed to install*************"
		exit 1
	else
		echo "**********install memtester Succcess**********"
	fi
fi

####Begin to test the Mem. Test time=24h####
killall -9 memtester 2> /dev/null
sleep 5
sync
echo 3 > /proc/sys/vm/drop_caches

#************test size*****************
compute_test_size
starttime=`date +%s`
echo "***********Mem_Stress Begin: `date +%Y.%m.%d.%H:%m:%S`***********"
for ((i=0;i <$Cpu_Num;i++))
do
	./memtester $perCPU_use 100 > ../mem_result/$i.txt &
done

cd ..
#若干memtester不会阻塞线程，立即经历下面过程

read -t $runtime -p "Cancel Memtest should enter [N/n]" reas
if [ "$reas" = "N" ] || [ "$reas" = "n" ]
then
	echo '********now stopping Memtester...***********'
	echo "user cancel!!" >>./mem_result/result_time.txt
fi
echo ""
#save result
stoptime=`date +%s`
count=`expr $stoptime - $starttime`
echo "stop time: $stoptime" >>./mem_result/result_time.txt
echo "test time: $count" >>./mem_result/result_time.txt

### set time to stop the test,usually 24h###
killall -9 memtester 2> /dev/null
echo "*********Mem_Stress Completed: `date +%Y.%m.%d.%H.%m.%S`************"
ps -ef | grep -i mem_stress 2>/dev/null| grep -v "grep" 2>/dev/null | awk '{print $2}' > ./"mempid"
while read mempid
do
	#echo $mempid
	kill -9 $mempid
done < ./"mempid"

rm -rf ./"mempid"

exit 0
