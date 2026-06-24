Scenario

You are hired as a contractor to help a university migrate an existing student system to a new platform using C++ language. Since the application already exists, its requirements exist as well, and they are outlined in the next section. You are responsible for implementing the part of the system based on these requirements. A list of data is provided as part of these requirements. This part of the system is responsible for reading and manipulating the provided data.
You must write a program containing two classes (i.e., Student and Roster). The program will maintain a current roster of students within a given course. Student data for the program include student ID, first name, last name, email address, age, an array of the number of days to complete each course, and degree program. This information can be found in the attached "studentData Table". The program will read a list of five students and use function calls to manipulate data (see part F4 in the requirements below). While parsing the list of data, the program should create student objects. The entire student list will be stored in one array of students called classRosterArray. Specific data-related output will be directed to the console.


Note: The errors in the email column are intentional; please copy each address exactly.



The data should be input as follows:

const string studentData[] = 

{"A1,John,Smith,John1989@gm ail.com,20,30,35,40,SECURITY", 

"A2,Suzan,Erickson,Erickson_1990@gmailcom,19,50,30,40,NETWORK", 

"A3,Jack,Napoli,The_lawyer99yahoo.com,19,20,40,33,SOFTWARE", 

"A4,Erin,Black,Erin.black@comcast.net,22,50,58,40,SECURITY", 

"A5,[firstname],[lastname],[emailaddress],[age],[numberofdaystocomplete3courses], SOFTWARE"};



You may not include third-party libraries. Your submission should include one ZIP file with all the necessary code files to compile, support, and run your application. You must also provide evidence of the program’s required functionality by taking a screen capture of the console run, saved as an image file.


Note: Each file must be an attachment no larger than 30 MB in size.



Requirements

Note: Wait until you have completed all the following prompts before you create your copy of the repository branch history.

B.  Modify the attached "studentData Table" to include your personal information as the last item.

C.  Create a C++ project in your integrated development environment (IDE) with the following files:

•   degree.h
•   student.h and student.cpp
•   roster.h and roster.cpp
•   main.cpp



Note: There must be a total of six code files.


D.  Define an enumerated type DegreeProgram for the degree programs containing the values SECURITY, NETWORK, and SOFTWARE.

Note: This information should be included in the degree.h file.



E.  For the Student class, do the following:

1.  Create the class Student in the files student.h and student.cpp, which includes each of the following private variables, using the correct data type for each:

•   student ID (string)
•   first name (string)
•   last name (string)
•   email address (string)
•   age (integer)
•   number of days to complete each course (array of integers)
•   degree program (DegreeProgram)



Note: All external access to any instance variables of the Student class must be done using accessor and mutator functions.



Note: The errors in the email column are intentional; please copy each address exactly.



2.  Create each of the following functions in the Student class:

a.  an accessor (i.e., getter) for each instance variable from part E1
b.  a mutator (i.e., setter) for each instance variable from part E1
c.  a constructor using all the input parameters provided in the table
d.  a print() function to print specific student data in the provided format:

A1 [tab] First Name: John [tab] Last Name: Smith [tab] Email: John1989@gmail.com [tab] Age: 20 [tab] daysInCourse: {35, 40, 55} Degree Program: Security



F.  Create a Roster class (roster.cpp) by doing the following:

1.  Create an array or vector of pointers named classRosterArray to hold the data provided in the "studentData Table."

2.  Create a student object for each student in the data table and populate classRosterArray.

a.  Parse each set of data identified in the "studentData Table."

b.  Add each student object to classRosterArray.

3.  Define the following public functions:

a.  void add(string studentID, string firstName, string lastName, string emailAddress, int age, int daysInCourse1, int daysInCourse2, int daysInCourse3, DegreeProgram degreeProgram) that sets the instance variables from part D1 and updates the roster

b.  void remove(string studentID) that removes students from the roster by student ID. If the student ID does not exist, the function prints an error message indicating that the student was not found

c.  void printAll()that loops through all the students in classRosterArray and calls the print() function for each student

d.  void printAverageDaysInCourse(string studentID) that correctly prints the average number of days in the three courses for the student whose studentID is passed in as the parameter

e.  void printInvalidEmails() that verifies student email addresses and displays all invalid email addresses to the user



Note:  A valid email should include an at sign ('@') and period ('.') and should not include a space (' ').



f.  void printByDegreeProgram(DegreeProgram degreeProgram) that prints out student information for a degree program specified by an enumerated type



Note:  All function signatures must match the task descriptions exactly.



g.  The destructor that will release memory claimed by the roster object.



G.  Demonstrate the program's required functionality by adding a main() function in main.cpp, which will contain the required function calls to achieve the following results:

1.  Print to the screen, via your application, the course title, the programming language used, your WGU student ID, and your name.

2.  Create an instance of the Roster class called classRoster.

3. Add each student to classRoster.

4.  Convert the following pseudo code to complete the rest of the main() function:

classRoster.printAll();

classRoster.printInvalidEmails();



//loop through classRosterArray and for each element:

classRoster.printAverageDaysInCourse(/*current_object's student id*/);

classRoster.printByDegreeProgram(SOFTWARE);
classRoster.remove("A3");
classRoster.printAll();
classRoster.remove("A3");

//expected: the above line should print a message saying such a student with this ID was not found.

//call the destructor to release the roster object from memory



H.  Demonstrate professional communication in the content and presentation of your submission.