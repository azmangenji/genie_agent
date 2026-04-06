# -*- coding: utf-8 -*-
"""
Created on Tue Jun 21 13:30:23 2023
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

"""
Support element:
#text#
Hello, this is example.
#title#
report summary
#bold#
Attention!
#list#
/proj/navi31n6/a0
/proj/navi31n6/a1
#table#
tile,run_dir
dfx_dft_t,/proj/navi31n6/a0/tiles
#table end#
#line#
"""


from dominate.tags import *
import argparse
import re
import random
class HtmlGenerator:
    def __init__(self):
        self.tableColorList = ["#0066cc","#0077b6","#005f99","#004c80"]
        self.colorIndex = random.randint(0,3)
        self.tableColor = self.tableColorList[self.colorIndex]
        self.style_applied = '''
                body {
                    font-family: 'Segoe UI', Arial, sans-serif;
                    font-size: 16px;
                    color: #333;
                    line-height: 1.6;
                    margin: 30px;
                }
                h2 {
                    color: #0066cc;
                    border-bottom: 2px solid #0066cc;
                    padding-bottom: 10px;
                    margin-top: 32px;
                    font-size: 22px;
                }
                h3 {
                    color: #0066cc;
                    margin-top: 24px;
                    font-size: 18px;
                }
                table.gridtable {
                    border-collapse: collapse;
                    margin: 18px 0;
                    font-size: 15px;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
                }
                table.gridtable th {
                    background-color: tableColor;
                    color: #ffffff;
                    padding: 13px 18px;
                    text-align: left;
                    font-weight: 600;
                    font-size: 15px;
                    border: 1px solid #004499;
                }
                table.gridtable td {
                    padding: 12px 18px;
                    border: 1px solid #ddd;
                    background-color: #ffffff;
                    text-align: left;
                    font-size: 15px;
                }
                table.gridtable tr:nth-child(even) td {
                    background-color: #f8f9fa;
                }
                table.gridtable tr:hover td {
                    background-color: #e8f4fc;
                }
                table.gridtable td.failed {
                    color: #dc3545;
                    font-weight: bold;
                }
                table.gridtable td.passrate {
                    font-weight: bold;
                    color: #28a745;
                }
                table.gridtable td.warning {
                    color: #ffc107;
                    font-weight: bold;
                }
                table.gridtable td.negative {
                    color: #dc3545;
                }
                table.gridtable td.positive {
                    color: #28a745;
                }
                a {
                    color: #0066cc;
                    text-decoration: none;
                }
                a:hover {
                    text-decoration: underline;
                }
                li {
                    margin-top: 8px;
                    padding-left: 6px;
                    font-size: 15px;
                    line-height: 1.6;
                }
                ul {
                    margin-top: 8px;
                    padding-left: 20px;
                }
                div {
                    margin-top: 12px;
                }
                hr {
                    border: none;
                    border-top: 2px solid #e0e0e0;
                    margin: 28px 0;
                }
                .title {
                    color: #0066cc;
                    font-weight: bold;
                    font-size: 17px;
                }
                .footer {
                    margin-top: 36px;
                    padding-top: 18px;
                    border-top: 1px solid #e0e0e0;
                    color: #666;
                    font-size: 14px;
                }
            '''
        self.style_applied = re.sub("tableColor",self.tableColor,self.style_applied)
        self.is_head = 0
        self.table_list = []
        self.thd = 0
        self.hello = ""
        self.text_list = []
        self.spec = "" 
        self.section={}
        self.id = 0

    def set_spec(self,hello,text_list,head_list,table_list,thd,spec):
        self.head_list = head_list
        self.table_list = table_list
        self.thd = thd
        self.hello = hello
        self.text_list = text_list
        self.spec = spec

    def read_spec(self,specFile,htmlFile):
        self.section['thn']= 2
        self.section['th']= 10.0
        self.section['div'] = "text"
        self.tableStart = 0
        spec = open(specFile,'r')
        html_root = html()
        # html head
        with html_root.add(head()):
             style(self.style_applied, type='text/css')
        # html body
        with html_root.add(body()):
            for line in spec:
                if len(line.split()) == 0:
                    self.section['div'] = "text"

                se = re.search('^#text#',line)
                if se:
                    self.section['div'] = "text"
                    print(self.section['div'])
                    continue
                se = re.search('^#th\s([0-9]+\s+[0-9]+\.[0-9]+)#',line)
                if se: 
                    #self.section['thn'] = se.group[0] 
                    #self.section['th'] = float(se.group[1])
                    print(self.section['div'])
                    continue
                se = re.search('^#table#',line)
                if se: 
                    self.section['div'] = "table"
                    self.tableStart = 1 
                    print(self.section['div'])
                    self.table_list = []
                    continue
                se = re.search('^#table end#',line)
                if se:
                    self.section['div'] = "table end"
                    print(self.section['div'])
                    if self.tableStart == 1:
                        self.create_table(self.table_list,self.section['thn'],self.section['th'])
                    self.tableStart = 0
                    continue
                se = re.search('^#line#',line)
                if se: 
                    self.create_line()
                    self.section['div'] = "line"
                    print(self.section['div'])
                    continue
                se = re.search('^#title#',line)
                if se: 
                    self.section['div'] = "title"
                    print(self.section['div'])
                    continue
                se = re.search('^#bold#',line)
                if se: 
                    self.section['div'] = "bold"
                    print(self.section['div'])
                    continue
                se = re.search('^#list#',line)
                if se:
                    self.section['div'] = "list"
                    print(self.section['div'])
                    continue
                se = re.search('^#img#',line)
                if se:
                    self.section['div'] = "img"
                    print(self.section['div'])
                    continue

                if self.section['div'] == "text":
                    self.create_text(line)
                if self.section['div'] == "title":
                    self.create_title(line,'#0B610B') 
                if self.section['div'] == "list":
                    self.create_list(line)
                if self.section['div'] == "line":
                    self.create_line()
                if self.section['div'] == "table":
                    self.table_list.append(line)
                if self.section['div'] == "img":
                    self.insert_image(line)

        self.generate_ending()
        with open(htmlFile, 'w') as f:
            f.write(html_root.render())
 
    def set_Hello(self,hello):
        hello_str = body
        hello_div = div(id='hello')
        hello_div.add(p('Dear Sir,'))
        hello_div.add(p(hello))

    def get_cell_class(self, cell_text):
        """Determine CSS class based on cell content"""
        cell_lower = cell_text.strip().lower()

        # Status-based coloring
        if cell_lower in ['pass', 'passed', 'success', 'completed']:
            return 'passrate'
        elif cell_lower in ['fail', 'failed', 'error']:
            return 'failed'
        elif cell_lower in ['warning']:
            return 'warning'

        # Number-based coloring (negative = red for timing violations)
        try:
            num = float(cell_text.strip())
            if num < 0:
                return 'negative'
        except ValueError:
            pass

        return ''

    def set_table_head(self,head_list):
        #head_list = ["Passed","Failed","Total","Pass","Rate,Details"]
        with tr():
            #th(style='background-color:white')
            # th colspan="3"> ffg1p05v0c_typrc100c_FuncFFG1p05v </th>
            for head in head_list.split(','):
                head = re.sub('\n','',head)
                head_arr = head.split()
                if len(head.split()) == 2:
                    th(head_arr[0],colspan=head_arr[1])
                else:
                    th(head)

    def create_table(self,table_list,thn,thd):
        result_div = div(id='test case result'+str(self.id))
        self.id = self.id + 1
        #print(table_list)
        with result_div.add(table(cls='gridtable')).add(tbody()):
            self.set_table_head(table_list[0])
            n = 0
            for line in table_list:
                line = re.sub('\n','',line)
                if n == 0:
                    n = 1
                    continue
                data_tr = tr()
                for cell in line.split(','):
                    #print("#cell",cell)
                    # table with list
                    if len(cell.split(';')) > 1:
                        #data_td = td(align="left")
                        data_ul = ul(align="left")
                        for t in cell.split(';'):
                            if re.search('\S+',t):
                                rem = re.search('mailto:.*subject=(.*)\&body',t)
                                if rem:
                                    data_ul += li(a(rem.group(1),href=t,align="left"))
                                    continue

                                if re.search('/proj/|http|/home/',t):
                                    t = re.sub(' ','',t)
                                    if  re.search('.log|.html|.png|http|.rpt|.pptx',t):
                                        lable = t.split('/')[-1]
                                        lable = lable.split('.')[0]
                                        print(lable,t)
                                        if  re.search('http',t):
                                            data_ul += li(a(lable,href=t,align="left"))
                                        else:
                                            data_ul += li(a(lable,href='http://logviewer-atl.amd.com/'+t,align="left"))
                                    else:
                                        data_ul += li(a(t,href='http://logviewer-atl.amd.com/'+t,align="left"))
                                else:
                                    data_ul += li(t,align="left")
                        data_tr+=td(data_ul,align="left")
                    else:
                        #data_td = td()
                        # table without list
                        if len(cell.split('::')) == 2:
                            style = "background-color: " + cell.split('::')[1] + ";\""
                            cell_text = cell.split('::')[0]
                        else:
                            cell_text = cell.split('::')[0]
                            style = ""

                        # Auto-detect cell class based on content
                        cell_cls = self.get_cell_class(cell_text)

                        rem = re.search('mailto:.*subject=(.*)\&body',cell_text)
                        if rem:
                            data_tr+=td(a(rem.group(1),href=cell_text),style=style,cls=cell_cls)
                            continue

                        if re.search('/proj/|http|/home/',cell_text):
                            if  re.search('.log|.html|.png|http|.rpt|.pptx',cell_text):
                                lable = cell_text.split('/')[-1]
                                lable = lable.split('.')[0]
                                if  re.search('http',cell_text):
                                    data_tr+=td(a(lable,href=cell_text),style=style,cls=cell_cls)
                                else:
                                    data_tr+=td(a(lable,href='http://logviewer-atl.amd.com/'+cell_text),style=style,cls=cell_cls)
                            else:
                                data_tr+=td(a(cell_text,href='http://logviewer-atl.amd.com/'+cell_text),style=style,cls=cell_cls)
                        else:
                            data_tr+=td(cell_text,style=style,cls=cell_cls)

                    se = re.search('^[0-9]+\.[0-9]+',cell)
                    #print(cell)
                    """
                    if se:
                        print(thn,"+",thd)
                        cell = round(float(cell),2)
                        if cell>thd:
                            data_tr += td(cell,cls='passrate')
                        else:
                            data_tr += td(cell,cls='failed') 
                        data_tr += td(cell)
                    else:
                        data_tr += td(cell)
                    """
            
    def create_line(self):
        div(hr(size=2, alignment='center', width='100%'))
    
    def create_title(self,title,color):
        div(b(font(title ,color=color)))
    
    def create_bold_text(self,text):
        div((b(font(text))))
    
    def create_text(self,text):
        span(text)
        #p(text)
        br()
        
    def create_list(self,text):
        list_div = div(id='list'+str(self.id)) 
        self.id = self.id+1
        list_text = li()
        rem = re.search('mailto:.*subject=(.*)\&body',text)
        if rem:
            list_text+=a(rem.group(1),href=text)
            list_text+= " "
        else:
            for word in text.split():
                if re.search('/proj/|http|/home/',word):
                    if  re.search('.log|.html|.png|http|.rpt|pptx',word):
                        lable = text.split('/')[-1]
                        lable = lable.split('.')[0]
                        if  re.search('http',word):
                            list_text+=a(lable,href=word)
                            list_text+= " "
                        else:
                            list_text+=a(lable,href='http://logviewer-atl.amd.com/'+word)
                            list_text+= " "
                    else:
                        list_text+=a(word,href='http://logviewer-atl.amd.com/'+word)
                        list_text+= " "
                else:
                    list_text+=word
                    list_text+= " "

        list_dot = ul()
        #list_dot += li(text)
        list_dot += list_text
        
    def generate_ending(self):
        br()
        with div(cls='footer'):
            p('Sent by PD Agent (Rosenhorn Agent Flow)')

    def insert_image(self,text):
        img(src=text)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='spec to html')
    parser.add_argument('--spec',type=str, default = "None",required=True,help="spec file")
    parser.add_argument('--html',type=str, default = "None",required=True,help="html file")
    args = parser.parse_args()

    hg=HtmlGenerator()
    hg.read_spec(args.spec,args.html,)
