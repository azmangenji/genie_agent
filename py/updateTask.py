"""
Created on Fri May 25 13:30:23 2023
@author: Simon Chen
"""

# Copyright (c) 2024 Chen, Simon ; simon1.chen@amd.com;  Advanced Micro Devices, Inc.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import argparse
import csv
import os
import time
import re
parser = argparse.ArgumentParser(description='Update task csv item')
parser.add_argument('--tag',type=str, default = "None",required=True,help="the task tag")
parser.add_argument('--source_run_dir',type=str, default = "None",required=True,help="the run dir info")
parser.add_argument('--target_run_dir',type=str, default = "None",required=True,help="the run dir info")
parser.add_argument('--status',type=str, default = "None",required=True,help="the running status")
parser.add_argument('--reply',type=str, default = "None",required=True,help="the reply content")
parser.add_argument('--html',type=str, default = "None",required=True,help="html file")
parser.add_argument('--tasksModelFile',type=str, default = "tasksModel.csv",required=True,help="tasksModelFile file")
args = parser.parse_args()
#print(args.tag)
def send_mail(sender,subject,mailBody,quote,html):
    mailBody = re.sub('\\\\n','\n',mailBody) 
    mail = 'cat ' + html + '| formail -I "To:' + sender + ' " -I "From: virtual tile owner" -I "MIME-Version:1.0" -I "Content-type:text/html;charset=utf-8" -I "Subject:Re:'+ \
             subject+ '" | sendmail -oi ' + sender

    #print(mail)
    p = os.popen(mail)
    # allow the mail sent out without thread kill
    time.sleep(2)

tasksModel = []
tasks_file = args.source_run_dir+"/"+args.tasksModelFile

# Skip if tasks model file doesn't exist (CLI mode)
if not os.path.exists(tasks_file):
    # For CLI mode, just exit silently - no task tracking needed
    exit(0)

with open(tasks_file,encoding='utf-8-sig') as f:
    reader = csv.DictReader(f)
    # here reader cannot be assign to taskMail directly, otherwise report IO error
    for i in reader:
        if i['tag'] == args.tag:
            #print(i['tag'])
            i['runDir'] = i['runDir'] + ':' + args.target_run_dir
            i['runDir'] = re.sub('::',':',i['runDir'])
            i['status'] = args.status
            i['reply'] = args.reply
            #print(i)
        tasksModel.append(i)
    f.close

with open(tasks_file, mode="w", encoding="utf-8-sig", newline="") as f:
    header_list = ["time", "tag","sender","subject", "mailBody","mailQuote","reply","instruction","runDir","status"]
    writer = csv.DictWriter(f,header_list)
    writer.writeheader()
    sorted(tasksModel, key=lambda x: x['time'])
    writer.writerows(tasksModel)
    f.close()
