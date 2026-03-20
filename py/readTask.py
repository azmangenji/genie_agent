"""
Created on Fri May 25 13:30:23 2023
@author: Simon Chen
"""
# This script is to add the original content as quotation
import argparse
import csv
import os
import time
import re
parser = argparse.ArgumentParser(description='Update task csv item')
parser.add_argument('--tag',type=str, default = "None",required=True,help="the task tag")
parser.add_argument('--tasksModelFile',type=str, default = "tasksModel.csv",required=False,help="the tasksModelFile")
parser.add_argument('--item',type=str, default = "None",required=True,help="the task item")
args = parser.parse_args()
# time,tag,sender,subject,mailBody,mailQuote,reply,instruction,runDir,status
with open(args.tasksModelFile,encoding='utf-8-sig') as f:
    reader = csv.DictReader(f)
    # here reader cannot be assign to taskMail directly, otherwise report IO error
    for i in reader:
        if i['tag'] == args.tag:
            print("Tag:",i['tag'],"\n","From:",i['sender'],"\n","Sent:",i['time'],"\n","Subject:",i['subject'],"\n","\n")
            # Convert back table if any
            found_table = 0
            for line in i[args.item].split('\n'):
                if re.search("^\|",line) and re.search("|$",line) and found_table == 0 :
                    print("#table#")
                    line_arr = line.split("|")
                    print(','.join(line_arr[1:-1]))
                    found_table = 1
                    continue
                if re.search("^\|",line) and re.search("|$",line) and found_table == 1 :
                    line_arr = line.split("|")
                    print(','.join(line_arr[1:-1]))
                    continue
                if found_table == 1:
                    print("#table end#")
                    found_table = 0
                    continue
                print(line)
            
    f.close

