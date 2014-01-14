--
-- MoneyMoney Web Banking Extension
-- http://moneymoney-app.com/api/webbanking
--
-- The MIT License (MIT)
--
-- Copyright (c) 2014 Moritz Müller
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
--
-- Support for LBS saving plans.
--


WebBanking{version     = 1.00,
           country     = "de",
           services    = {"Bausparvertrag LBS"},
           url         = "https://kundenservice.lbs.de/",
           description = "Bausparverträge abfragen"}


function SupportsBank (protocol, bankCode)
  return bankCode == "Bausparvertrag LBS"
         and
         protocol == ProtocolWebBanking
end

local function strToDate (str)
  -- Helper function for converting localized date strings to timestamps.
  local d, m, y = string.match(str, "(%d%d).(%d%d).(%d%d%d%d)")
  return os.time{year=y, month=m, day=d}
end


local function strToAmount (str)
  -- Helper function for converting localized amount strings to Lua numbers.
  str = string.gsub(string.gsub(str, "[^%d,-]", ""), ",", ".")
  return tonumber(str)
end


function InitializeSession (protocol, bankCode, username, customer, password)
  cardName = bankCode

credentials = {
    username = username,
    password = password
  }
  -- Create HTTPS connection object.
  connection = Connection()
  connection.language = "de-de"

  -- Fetch login page.
  url = "https://kundenservice.lbs.de/bw/guiServlet"
  html = HTML(connection:get(url))

  -- Check for errors.
  if html:xpath("//title"):text() == "Error" then
    local message = html:xpath("//p"):text()
    print("Response: " .. message)
    return "Der Server Ihrer Bank meldet einen internen Fehler. Bitte versuchen Sie es später noch einmal."
  end

  -- Fill in login credentials.
  html:xpath("//input[@name='IN_ID']"):attr("value", username)
  html:xpath("//input[@name='IN_PIN']"):attr("value", password)

  -- Submit login form.
  html = HTML(connection:request(html:xpath("//form"):submit()))
  
  -- Check for errors.
  if html:xpath("//title"):text() == "Error" then
    local message = html:xpath("//p"):text()
    print("Response: " .. message)
    return "Der Server Ihrer Bank meldet einen internen Fehler. Bitte versuchen Sie es später noch einmal."
  end

end


function ListAccounts (knownAccounts)
  local accounts = {}
  local owner = owner
  
  html:xpath("//form[contains(@name,'kontoausgabe')]//tr"):each(function (index, tr)
    if index ~= "1" then
		local name = html:xpath("//tr[" .. index .. "]/td[6]"):text()
		local accountNumber = html:xpath("//tr[" .. index .. "]/td[2]"):text()
		local balance = html:xpath("//tr[" .. index .. "]/td[4]"):text()
		
		if string.len(name) > 0 then
			local account = {
				bankCode      = bankCode,
				name          = name,
				accountNumber = accountNumber,
				owner         = owner,
				currency      = string.sub(balance, -3),
				type          = AccountTypeSavings
			}
			table.insert(accounts, account)
        end
    end
  end)
  
  return accounts
end


function RefreshAccount (account, since)
  local balance      = nil
  local transactions = nil


  local accountNumberSelected = account.accountNumber
  
  res = InitializeSession(nil, nil, credentials.username, nil, credentials.password)
       if res then
         return res
       end
  
  html:xpath("//td[@class='radio']"):each(function (index, td)
	html:xpath("//td[@class='radio']/input"):attr("checked", "")
  end)
    
  html:xpath("//form[@name='kontoausgabe']//tr"):each(function (index, tr)
  	local name = html:xpath("//tr[" .. index .. "]/td[6]"):text()
	
	if string.len(name) > 0 then	
		local accountNumber = html:xpath("//form[@name='kontoausgabe']//tr[" .. index .. "]/td[2]"):text()
	
		if accountNumberSelected == accountNumber then
			-- load balance
			balance = strToAmount(html:xpath("//form[@name='kontoausgabe']//tr[" .. index .. "]/td[4]"):text())
	
			-- set account
			html:xpath("//form[@name='kontoausgabe']//tr[" .. index .. "]/td[1]/input"):attr("checked", "checked")
			print("selected: " .. name)
		end
	end
  end)
  
  -- open transactions
  html = HTML(connection:request(html:xpath("//input[@name='REQ_ID.BSVUMS']"):click()))

  transactions = {}
  html:xpath("//table//tr"):each(function (index, tr)
  
	  local name = html:xpath("(//table//tr)[" .. index .. "]/td[4]"):text()
  
	  if string.len(name) > 0 then
		  -- parse through statements
		  
		  local transaction = {}
		  transaction.bookingDate = strToDate(html:xpath("(//table//tr)[" .. index .. "]/td[1]"):text())
		  transaction.valueDate = strToDate(html:xpath("(//table//tr)[" .. index .. "]/td[2]"):text())
		  transaction.amount = strToAmount(html:xpath("(//table//tr)[" .. index .. "]/td[3]"):text())
		  transaction.currency = string.sub(html:xpath("(//table//tr)[" .. index .. "]/td[3]"):text(), -3)
		  transaction.bookingText = html:xpath("(//table//tr)[" .. index .. "]/td[4]"):text()
		  table.insert (transactions, transaction)
	  end
  end)
  return {balance=balance, transactions=transactions}

end


function EndSession ()
  -- Navigate to logout page.
  local a = html:xpath("//a[contains(text(),'beenden')]")
  if a:length() > 0 then
    connection:request(a:click())
  end
end
