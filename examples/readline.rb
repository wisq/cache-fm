begin
  if Reiadline::VERSION =~ /EditLine/ then
    puts "*** EditLine detected.  If used by IRB, you will have problems! ***"
  else
    puts "--- Normal Readline detected.  Should be okay. ---"
  end
rescue NameError
  puts "--- No Readline detected.  Should be okay. ---"
end

$main = Thread.current
Thread.new do
  for i in 1..5 do
    sleep(1)
    puts i
  end

  puts "--- Complete!  Assuming you didn't type anything, your IRB is okay. ---"
  $main.kill
end
